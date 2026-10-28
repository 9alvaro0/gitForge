import Foundation
import Testing
@testable import gitForge

@Suite("TokenRefresher")
struct TokenRefresherTests {
    static let instance = HostingInstance(kind: .gitlab, host: "gitlab.example.test", oauthClientId: "test-client")
    static let now = Date(timeIntervalSince1970: 2_000_000)
    let account = HostingAccount(instanceId: TokenRefresherTests.instance.id, method: .oauth)

    static func grant(_ n: Int, refresh: Bool = true) -> TokenGrant {
        TokenGrant(accessToken: "access-\(n)", refreshToken: refresh ? "refresh-\(n)" : nil, expiresIn: 7200, scopes: nil)
    }

    private func setup(expiresIn: TimeInterval?, refreshToken: String? = "refresh-1",
                       refresh: @escaping @Sendable (String) async throws -> TokenGrant = { _ in TokenRefresherTests.grant(2) },
                       rejected: LockedList<UUID> = LockedList())
        -> (TokenRefresher, InMemoryAccountSecretStore, FakeAuthClient) {
        let secrets = InMemoryAccountSecretStore()
        try? secrets.write(AccountSecret(accessToken: "access-1", refreshToken: refreshToken,
                                         accessTokenExpiresAt: expiresIn.map { Self.now.addingTimeInterval($0) }),
                           for: account.id)
        let client = FakeAuthClient(instance: Self.instance, refresh: refresh)
        let refresher = TokenRefresher(secrets: secrets, makeClient: { _ in client }, now: { Self.now },
                                       onRefreshRejected: { rejected.append($0) })
        return (refresher, secrets, client)
    }

    @Test("Refresh only with a refresh token and under 5 minutes left")
    func needsRefresh() {
        let now = Self.now
        #expect(!TokenRefresher.needsRefresh(AccountSecret(accessToken: "a", accessTokenExpiresAt: now - 10), now: now))
        #expect(!TokenRefresher.needsRefresh(AccountSecret(accessToken: "a", refreshToken: "r"), now: now))
        #expect(!TokenRefresher.needsRefresh(AccountSecret(accessToken: "a", refreshToken: "r", accessTokenExpiresAt: now + 600), now: now))
        #expect(TokenRefresher.needsRefresh(AccountSecret(accessToken: "a", refreshToken: "r", accessTokenExpiresAt: now + 240), now: now))
        #expect(TokenRefresher.needsRefresh(AccountSecret(accessToken: "a", refreshToken: "r", accessTokenExpiresAt: now - 1), now: now))
    }

    @Test("A token with time left is used as is")
    func fresh() async throws {
        let (refresher, _, client) = setup(expiresIn: 3600)
        #expect(try await refresher.accessToken(for: account, on: Self.instance) == "access-1")
        #expect(client.refreshCalls.isEmpty)
    }

    @Test("Under 5 minutes left: refreshed, and the rotated pair is saved")
    func refreshesNearExpiry() async throws {
        let (refresher, secrets, client) = setup(expiresIn: 120)
        #expect(try await refresher.accessToken(for: account, on: Self.instance) == "access-2")
        #expect(client.refreshCalls == ["refresh-1"])
        #expect(secrets.read(account.id) == AccountSecret(accessToken: "access-2", refreshToken: "refresh-2",
                                                          accessTokenExpiresAt: Self.now + 7200))
    }

    @Test("If the server keeps the refresh token, the old one stays")
    func keepsRefreshToken() async throws {
        let (refresher, secrets, _) = setup(expiresIn: 120, refresh: { _ in Self.grant(2, refresh: false) })
        _ = try await refresher.accessToken(for: account, on: Self.instance)
        #expect(secrets.read(account.id)?.refreshToken == "refresh-1")
    }

    @Test("Simultaneous callers share one refresh (the refresh token is single-use)")
    func oneRefreshAtATime() async throws {
        let (refresher, _, client) = setup(expiresIn: 120, refresh: { _ in
            try await Task.sleep(for: .milliseconds(50))
            return Self.grant(2)
        })
        let account = self.account
        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<5 {
                group.addTask { try await refresher.accessToken(for: account, on: Self.instance) }
            }
            return try await group.reduce(into: [String]()) { $0.append($1) }
        }
        #expect(tokens == Array(repeating: "access-2", count: 5))
        #expect(client.refreshCalls == ["refresh-1"])
    }

    @Test("A 401 refreshes once and retries with the new token")
    func retriesAfter401() async throws {
        let (refresher, _, client) = setup(expiresIn: 3600)
        let used = LockedList<String>()
        let result = try await refresher.perform(for: account, on: Self.instance) { token in
            used.append(token)
            if token == "access-1" { throw HostingAuthError.unauthorized }
            return "ok with \(token)"
        }
        #expect(result == "ok with access-2")
        #expect(used.values == ["access-1", "access-2"])
        #expect(client.refreshCalls == ["refresh-1"])
    }

    @Test("A second 401 after the retry goes back to the caller")
    func secondUnauthorized() async {
        let (refresher, _, client) = setup(expiresIn: 3600)
        await #expect(throws: HostingAuthError.unauthorized) {
            try await refresher.perform(for: self.account, on: Self.instance) { _ -> String in throw HostingAuthError.unauthorized }
        }
        #expect(client.refreshCalls.count == 1)
    }

    @Test("Accounts that can't refresh pass a 401 straight through")
    func noRefreshToken() async {
        let (refresher, _, client) = setup(expiresIn: nil, refreshToken: nil)
        await #expect(throws: HostingAuthError.unauthorized) {
            try await refresher.perform(for: self.account, on: Self.instance) { _ -> String in throw HostingAuthError.unauthorized }
        }
        #expect(client.refreshCalls.isEmpty)
    }

    @Test("A rejected refresh reports the account; a network failure doesn't")
    func rejectedVersusOffline() async {
        let rejected = LockedList<UUID>()
        let (refresher, _, _) = setup(expiresIn: 60, refresh: { _ in throw HostingAuthError.refreshRejected }, rejected: rejected)
        await #expect(throws: HostingAuthError.refreshRejected) {
            try await refresher.accessToken(for: self.account, on: Self.instance)
        }
        #expect(rejected.values == [account.id])

        let offline = LockedList<UUID>()
        let (other, _, _) = setup(expiresIn: 60, refresh: { _ in throw HostingAuthError.network("offline") }, rejected: offline)
        await #expect(throws: HostingAuthError.network("offline")) {
            try await other.accessToken(for: self.account, on: Self.instance)
        }
        #expect(offline.values.isEmpty)
    }

    @Test("A caller's own rejection (git's 401) refreshes once and retries")
    func customRejection() async throws {
        struct GitRefused: Error {}
        let (refresher, _, client) = setup(expiresIn: 3600)
        let used = LockedList<String>()
        let result = try await refresher.perform(for: account, on: Self.instance, retryingWhen: { $0 is GitRefused }) { token in
            used.append(token)
            if token == "access-1" { throw GitRefused() }
            return token
        }
        #expect(result == "access-2")
        #expect(used.values == ["access-1", "access-2"])
        #expect(client.refreshCalls == ["refresh-1"])
    }

    @Test("Without a refresh token the caller's own error comes back unchanged")
    func rethrowsOriginal() async {
        struct GitRefused: Error, Equatable {}
        let (refresher, _, client) = setup(expiresIn: nil, refreshToken: nil)
        await #expect(throws: GitRefused()) {
            try await refresher.perform(for: self.account, on: Self.instance, retryingWhen: { $0 is GitRefused }) { _ -> String in
                throw GitRefused()
            }
        }
        #expect(client.refreshCalls.isEmpty)
    }

    @Test("After a rejected token: one refresh, the new token comes back")
    func refreshAfterRejection() async throws {
        let (refresher, _, client) = setup(expiresIn: 3600)
        #expect(try await refresher.refreshAfterRejection(for: account, on: Self.instance, rejected: "access-1") == "access-2")
        #expect(client.refreshCalls == ["refresh-1"])
    }

    @Test("An account that can't refresh says unauthorized after a rejection")
    func cannotRefreshAfterRejection() async {
        let (refresher, _, client) = setup(expiresIn: nil, refreshToken: nil)
        await #expect(throws: HostingAuthError.unauthorized) {
            try await refresher.refreshAfterRejection(for: self.account, on: Self.instance, rejected: "access-1")
        }
        #expect(client.refreshCalls.isEmpty)
    }

    @Test("No secret in the Keychain: missingSecret")
    func missingSecret() async {
        let refresher = TokenRefresher(secrets: InMemoryAccountSecretStore(), makeClient: { _ in FakeAuthClient() }, now: { Self.now })
        await #expect(throws: HostingAuthError.missingSecret) {
            try await refresher.accessToken(for: self.account, on: Self.instance)
        }
    }

    @Test("The Keychain refuses the refreshed pair: kept in memory and saved on a later read")
    func keepsUnsavedSecret() async throws {
        let (refresher, secrets, client) = setup(expiresIn: 120)
        secrets.failWrites = true
        #expect(try await refresher.accessToken(for: account, on: Self.instance) == "access-2")
        #expect(secrets.read(account.id)?.accessToken == "access-1")
        // The single-use refresh token isn't spent again.
        #expect(try await refresher.accessToken(for: account, on: Self.instance) == "access-2")
        #expect(client.refreshCalls == ["refresh-1"])

        secrets.failWrites = false
        _ = try await refresher.accessToken(for: account, on: Self.instance)
        #expect(secrets.read(account.id)?.refreshToken == "refresh-2")
    }

    @Test("A refresh starts from the Keychain, not memory: a pair another copy of the app rotated is used")
    func refreshRereadsKeychain() async throws {
        let keychain = InMemoryAccountSecretStore()
        try keychain.write(AccountSecret(accessToken: "access-1", refreshToken: "refresh-1",
                                         accessTokenExpiresAt: Self.now + 120), for: account.id)
        let secrets = CachingAccountSecretStore(keychain)
        #expect(secrets.read(account.id)?.accessToken == "access-1")
        // Another copy (a Debug build next to the installed one) refreshes
        // first and spends refresh-1, which works only once.
        let rotated = AccountSecret(accessToken: "access-9", refreshToken: "refresh-9",
                                    accessTokenExpiresAt: Self.now + 7200)
        try keychain.write(rotated, for: account.id)
        let client = FakeAuthClient(instance: Self.instance, refresh: { _ in Self.grant(2) })
        let refresher = TokenRefresher(secrets: secrets, makeClient: { _ in client }, now: { Self.now })
        #expect(try await refresher.accessToken(for: account, on: Self.instance) == "access-9")
        #expect(client.refreshCalls.isEmpty)
        #expect(secrets.read(account.id) == rotated)
    }

    @Test("Reconnected while a refresh runs: the new connection is kept")
    func reconnectDuringRefresh() async throws {
        let gate = AsyncGate()
        let (refresher, secrets, _) = setup(expiresIn: 120, refresh: { _ in
            await gate.wait()
            return Self.grant(2)
        })
        let account = self.account
        let pending = Task { try await refresher.accessToken(for: account, on: Self.instance) }
        await gate.waiting()
        let reconnected = AccountSecret(accessToken: "access-new", refreshToken: "refresh-new",
                                        accessTokenExpiresAt: Self.now + 7200)
        try secrets.write(reconnected, for: account.id)
        gate.open()
        #expect(try await pending.value == "access-new")
        #expect(secrets.read(account.id) == reconnected)
    }

    @Test("Reconnected while a refresh is rejected: the account isn't marked expired")
    func reconnectDuringRejectedRefresh() async throws {
        let gate = AsyncGate()
        let rejected = LockedList<UUID>()
        let (refresher, secrets, _) = setup(expiresIn: 120, refresh: { _ in
            await gate.wait()
            throw HostingAuthError.refreshRejected
        }, rejected: rejected)
        let account = self.account
        let pending = Task { try await refresher.accessToken(for: account, on: Self.instance) }
        await gate.waiting()
        try secrets.write(AccountSecret(accessToken: "access-new", refreshToken: "refresh-new",
                                        accessTokenExpiresAt: Self.now + 7200), for: account.id)
        gate.open()
        #expect(try await pending.value == "access-new")
        #expect(rejected.values.isEmpty)
    }

    @Test("A caller cancelled during a shared refresh doesn't spoil it for the others")
    func cancelledCallerDuringSharedRefresh() async throws {
        let gate = AsyncGate()
        let (refresher, secrets, client) = setup(expiresIn: 120, refresh: { _ in
            await gate.wait()
            return Self.grant(2)
        })
        let account = self.account
        let first = Task { try await refresher.accessToken(for: account, on: Self.instance) }
        await gate.waiting()
        let second = Task { try await refresher.accessToken(for: account, on: Self.instance) }
        first.cancel()
        gate.open()
        #expect(try await second.value == "access-2")
        _ = try? await first.value
        #expect(client.refreshCalls == ["refresh-1"])
        #expect(secrets.read(account.id)?.refreshToken == "refresh-2")
    }
}
