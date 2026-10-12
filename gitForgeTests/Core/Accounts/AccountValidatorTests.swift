import Foundation
import Testing
@testable import gitForge

@Suite("AccountValidator", .serialized)
@MainActor
struct AccountValidatorTests {
    nonisolated static let now = Date(timeIntervalSince1970: 3_000_000_000)
    nonisolated static let hour: TimeInterval = 60 * 60
    nonisolated static let user = HostingUser(login: "tanuki-test", displayName: "Tanuki Test",
                                              avatarURL: URL(string: "https://gitlab.example.test/a.png"))

    private func makeStore(clientIds: OAuthClientIDs = .none) -> (AccountStore, InMemoryAccountSecretStore) {
        let secrets = InMemoryAccountSecretStore()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-validator-\(UUID().uuidString)")
        return (AccountStore(directory: dir, secrets: secrets, clientIds: clientIds), secrets)
    }

    private func validator(_ store: AccountStore, _ client: FakeAuthClient) -> AccountValidator {
        let refresher = TokenRefresher(secrets: store.secrets, makeClient: { _ in client }, now: { Self.now },
                                       onRefreshRejected: { id in await store.markNeedsAttention(id, .expired) })
        return AccountValidator(store: store, refresher: refresher, makeClient: { _ in client }, now: { Self.now })
    }

    private func addCopied(_ store: AccountStore, token: String = "test-pat", lastValidatedAt: Date? = nil) throws -> HostingAccount {
        let account = HostingAccount(instanceId: HostingInstance.gitLabDotCom.id, method: .personalToken,
                                     lastValidatedAt: lastValidatedAt, status: .unverified)
        try store.addAccount(account, secret: AccountSecret(accessToken: token))
        return account
    }

    @Test("A copied token gets its login, identity, scopes and ok")
    func fillsCopiedAccount() async throws {
        let (store, _) = makeStore()
        _ = try addCopied(store)
        let client = FakeAuthClient(validate: { _ in TokenValidation(user: Self.user, scopes: ["api"], expiresAt: nil) })
        await validator(store, client).validateDueAccounts()
        let saved = try #require(store.accounts.first)
        #expect(saved.login == "tanuki-test")
        #expect(saved.displayName == "Tanuki Test")
        #expect(saved.scopes == ["api"])
        #expect(saved.status == .ok)
        #expect(saved.lastValidatedAt == Self.now)
        #expect(client.validatedTokens == ["test-pat"])
    }

    @Test("Under 7 days to expiry: expiringSoon")
    func expiringSoon() async throws {
        let (store, _) = makeStore()
        _ = try addCopied(store)
        let client = FakeAuthClient(validate: { _ in TokenValidation(user: Self.user, scopes: ["api"], expiresAt: Self.now + 72 * Self.hour) })
        await validator(store, client).validateDueAccounts()
        #expect(store.accounts[0].status == .expiringSoon)
        #expect(store.accounts[0].expiresAt == Self.now + 72 * Self.hour)
    }

    @Test("A 401 marks the account revoked")
    func revoked() async throws {
        let (store, _) = makeStore()
        _ = try addCopied(store)
        await validator(store, FakeAuthClient(validate: { _ in throw HostingAuthError.unauthorized })).validateDueAccounts()
        #expect(store.accounts[0].status == .needsAttention(.revoked))
        #expect(store.accounts[0].lastValidatedAt == Self.now)
    }

    @Test("A token rejected after its expiry date needs attention as expired, not revoked")
    func expiredToken() async throws {
        let (store, _) = makeStore()
        let account = HostingAccount(instanceId: HostingInstance.gitLabDotCom.id, login: "tanuki-test",
                                     method: .personalToken, expiresAt: Self.now - Self.hour, status: .ok)
        try store.addAccount(account, secret: AccountSecret(accessToken: "test-pat"))
        await validator(store, FakeAuthClient(validate: { _ in throw HostingAuthError.unauthorized })).validateDueAccounts()
        #expect(store.accounts[0].status == .needsAttention(.expired))
    }

    @Test("Missing scopes mark it missingScopes")
    func missingScopes() async throws {
        let (store, _) = makeStore()
        _ = try addCopied(store)
        await validator(store, FakeAuthClient(validate: { _ in throw HostingAuthError.missingScopes(["api"]) })).validateDueAccounts()
        #expect(store.accounts[0].status == .needsAttention(.missingScopes))
    }

    @Test("A read_api token keeps its login and scopes and needs attention for missing scopes")
    func readOnlyToken() async throws {
        let (store, _) = makeStore()
        _ = try addCopied(store)
        let client = FakeAuthClient(validate: { _ in TokenValidation(user: Self.user, scopes: ["read_api"], expiresAt: nil) })
        await validator(store, client).validateDueAccounts()
        #expect(store.accounts[0].login == "tanuki-test")
        #expect(store.accounts[0].scopes == ["read_api"])
        #expect(store.accounts[0].status == .needsAttention(.missingScopes))
    }

    @Test("A 403 that isn't about scopes, TLS or a 5xx leave the account as it was")
    func untouchedByOtherFailures() async throws {
        for failure in [HostingAuthError.server(403), .tls("bad"), .server(502), .cancelled] {
            let (store, _) = makeStore()
            _ = try addCopied(store)
            await validator(store, FakeAuthClient(validate: { _ in throw failure })).validateDueAccounts()
            #expect(store.accounts[0].status == .unverified)
            #expect(store.accounts[0].lastValidatedAt == nil)
        }
    }

    @Test("Offline: status and last check stay as they were")
    func offline() async throws {
        let (store, _) = makeStore()
        _ = try addCopied(store)
        await validator(store, FakeAuthClient(validate: { _ in throw HostingAuthError.network("offline") })).validateDueAccounts()
        #expect(store.accounts[0].status == .unverified)
        #expect(store.accounts[0].lastValidatedAt == nil)
    }

    @Test("Checked under 24 h ago: skipped; over 24 h: checked again")
    func onceADay() async throws {
        let (store, _) = makeStore()
        _ = try addCopied(store, token: "recent", lastValidatedAt: Self.now - 2 * Self.hour)
        _ = try addCopied(store, token: "stale", lastValidatedAt: Self.now - 25 * Self.hour)
        let client = FakeAuthClient(validate: { _ in TokenValidation(user: Self.user, scopes: ["api"], expiresAt: nil) })
        await validator(store, client).validateDueAccounts()
        #expect(client.validatedTokens == ["stale"])
        #expect(AccountValidator.isDue(store.accounts[0], now: Self.now) == false)
    }

    @Test("A GitLab OAuth session whose refresh is refused needs attention as expired")
    func refreshRefused() async throws {
        let (store, _) = makeStore(clientIds: OAuthClientIDs(gitHub: nil, gitLab: "test-client"))
        let account = HostingAccount(instanceId: HostingInstance.gitLabDotCom.id, login: "tanuki-test", method: .oauth, status: .ok)
        try store.addAccount(account, secret: AccountSecret(accessToken: "old", refreshToken: "refresh-1",
                                                            accessTokenExpiresAt: Self.now + 60))
        let client = FakeAuthClient(refresh: { _ in throw HostingAuthError.refreshRejected },
                                    validate: { _ in TokenValidation(user: Self.user, scopes: nil, expiresAt: nil) })
        await validator(store, client).validateDueAccounts()
        #expect(store.accounts[0].status == .needsAttention(.expired))
        #expect(client.validatedTokens.isEmpty)
    }

    @Test("A GitLab OAuth session about to expire is refreshed before the check")
    func refreshesFirst() async throws {
        let (store, secrets) = makeStore(clientIds: OAuthClientIDs(gitHub: nil, gitLab: "test-client"))
        let account = HostingAccount(instanceId: HostingInstance.gitLabDotCom.id, method: .oauth, scopes: ["api"])
        try store.addAccount(account, secret: AccountSecret(accessToken: "old", refreshToken: "refresh-1",
                                                            accessTokenExpiresAt: Self.now + 60))
        let client = FakeAuthClient(
            refresh: { _ in TokenGrant(accessToken: "new", refreshToken: "refresh-2", expiresIn: 7200, scopes: nil) },
            validate: { _ in TokenValidation(user: Self.user, scopes: nil, expiresAt: nil) })
        await validator(store, client).validateDueAccounts()
        #expect(client.validatedTokens == ["new"])
        #expect(secrets.read(account.id)?.refreshToken == "refresh-2")
        #expect(store.accounts[0].status == .ok)
        #expect(store.accounts[0].scopes == ["api"])
    }
}
