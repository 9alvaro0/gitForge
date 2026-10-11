import Foundation
import Testing
@testable import gitForge

private struct Legacy: LegacyTokenSource {
    var tokens: [String: String]
    func legacyHosts() throws -> [String] { Array(tokens.keys).sorted() }
    func legacyToken(for host: String) throws -> String? { tokens[host] }
}

@Suite("Accounts — status and connection writes", .serialized)
@MainActor
struct AccountConnectionStoreTests {
    nonisolated static let now = Date(timeIntervalSince1970: 2_000_000_000)
    nonisolated static let day: TimeInterval = 24 * 60 * 60
    nonisolated static let tanuki = TokenValidation(
        user: HostingUser(login: "tanuki-test", displayName: "Tanuki Test", avatarURL: URL(string: "https://gitlab.example.test/a.png")),
        scopes: ["api"], expiresAt: nil)

    private static func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-connect-\(UUID().uuidString)")
    }

    // MARK: Policy

    @Test("Status from the token's expiry")
    func statusPolicy() {
        #expect(AccountStatusPolicy.status(expiresAt: nil, now: Self.now) == .ok)
        #expect(AccountStatusPolicy.status(expiresAt: Self.now + 30 * Self.day, now: Self.now) == .ok)
        #expect(AccountStatusPolicy.status(expiresAt: Self.now + 6 * Self.day, now: Self.now) == .expiringSoon)
        #expect(AccountStatusPolicy.status(expiresAt: Self.now - 1, now: Self.now) == .needsAttention(.expired))
    }

    @Test("Which errors say something about the account")
    func reasons() {
        #expect(AccountStatusPolicy.reason(for: .unauthorized) == .revoked)
        #expect(AccountStatusPolicy.reason(for: .inactiveToken) == .revoked)
        #expect(AccountStatusPolicy.reason(for: .refreshRejected) == .expired)
        #expect(AccountStatusPolicy.reason(for: .missingScopes(["api"])) == .missingScopes)
        #expect(AccountStatusPolicy.reason(for: .forbidden) == .missingScopes)
        #expect(AccountStatusPolicy.reason(for: .network("offline")) == nil)
        #expect(AccountStatusPolicy.reason(for: .tls("bad")) == nil)
        #expect(AccountStatusPolicy.reason(for: .server(502)) == nil)
        #expect(AccountStatusPolicy.reason(for: .missingSecret) == nil)
    }

    // MARK: connectAccount

    @Test("A new connection is saved validated, with its secret")
    func connectsNew() throws {
        let secrets = InMemoryAccountSecretStore()
        let store = AccountStore(directory: Self.tempDir(), secrets: secrets, clientIds: .none)
        let account = try store.connectAccount(instanceId: HostingInstance.gitLabDotCom.id, method: .personalToken,
                                               validation: Self.tanuki, secret: AccountSecret(accessToken: "test-pat"), now: Self.now)
        #expect(store.accounts == [account])
        #expect(account.login == "tanuki-test")
        #expect(account.displayName == "Tanuki Test")
        #expect(account.scopes == ["api"])
        #expect(account.status == .ok)
        #expect(account.lastValidatedAt == Self.now)
        #expect(secrets.read(account.id)?.accessToken == "test-pat")
    }

    @Test("Scopes: the validation's, else the grant's, else none")
    func connectScopes() throws {
        let store = AccountStore(directory: Self.tempDir(), secrets: InMemoryAccountSecretStore(), clientIds: .none)
        var noScopes = Self.tanuki
        noScopes.scopes = nil
        let oauth = try store.connectAccount(instanceId: HostingInstance.gitLabDotCom.id, method: .oauth, validation: noScopes,
                                             grantedScopes: ["api", "read_user"], secret: AccountSecret(accessToken: "a"), now: Self.now)
        #expect(oauth.scopes == ["api", "read_user"])
        noScopes.user.login = "other"
        let fineGrained = try store.connectAccount(instanceId: HostingInstance.gitHubDotCom.id, method: .personalToken,
                                                   validation: noScopes, secret: AccountSecret(accessToken: "b"), now: Self.now)
        #expect(fineGrained.scopes == [])
    }

    @Test("Reconnecting the same login updates the account in place: id, profile link and repo assignments stay")
    func reconnectsInPlace() throws {
        let secrets = InMemoryAccountSecretStore()
        let store = AccountStore(directory: Self.tempDir(), secrets: secrets, clientIds: .none)
        let profile = UUID()
        let original = HostingAccount(instanceId: HostingInstance.gitLabDotCom.id, login: "Tanuki-Test",
                                      method: .personalToken, linkedProfileId: profile)
        try store.addAccount(original, secret: AccountSecret(accessToken: "old-pat"))
        store.assign(original.id, repoPath: "/r/app", remoteName: "origin")

        let updated = try store.connectAccount(instanceId: HostingInstance.gitLabDotCom.id, method: .oauth, validation: Self.tanuki,
                                               secret: AccountSecret(accessToken: "oauth-access", refreshToken: "r"), now: Self.now)
        #expect(updated.id == original.id)
        #expect(store.accounts.count == 1)
        #expect(store.accounts[0].method == .oauth)
        #expect(store.accounts[0].linkedProfileId == profile)
        #expect(store.assignedAccountId(repoPath: "/r/app", remoteName: "origin") == original.id)
        #expect(secrets.read(original.id)?.accessToken == "oauth-access")
    }

    @Test("If the Keychain refuses the new secret, the account isn't touched")
    func reconnectKeychainFails() throws {
        let secrets = InMemoryAccountSecretStore()
        let store = AccountStore(directory: Self.tempDir(), secrets: secrets, clientIds: .none)
        let original = HostingAccount(instanceId: HostingInstance.gitLabDotCom.id, login: "tanuki-test", method: .personalToken)
        try store.addAccount(original, secret: AccountSecret(accessToken: "old-pat"))
        secrets.failWrites = true
        #expect(throws: (any Error).self) {
            try store.connectAccount(instanceId: HostingInstance.gitLabDotCom.id, method: .oauth, validation: Self.tanuki,
                                     secret: AccountSecret(accessToken: "new"), now: Self.now)
        }
        #expect(store.accounts == [original])
        #expect(secrets.read(original.id)?.accessToken == "old-pat")
    }

    @Test("A reconnected copied account is no longer fed by the old token, now or after a relaunch")
    func reconnectDetachesLegacy() throws {
        let dir = Self.tempDir()
        let secrets = InMemoryAccountSecretStore()
        let legacy = Legacy(tokens: ["gitlab.com": "old-pat"])
        let store = AccountStore(directory: dir, secrets: secrets, clientIds: .none)
        store.migrateLegacyTokens(from: legacy)
        let copied = try #require(store.accounts.first)
        store.applyValidation(Self.tanuki, to: copied.id, now: Self.now)

        try store.connectAccount(instanceId: HostingInstance.gitLabDotCom.id, method: .personalToken, validation: Self.tanuki,
                                 secret: AccountSecret(accessToken: "new-pat"), now: Self.now)
        store.migrateLegacyTokens(from: legacy)
        #expect(store.accounts.count == 1)
        #expect(secrets.read(copied.id)?.accessToken == "new-pat")
        #expect(store.detachedLegacyHosts == ["gitlab.com"])

        let relaunched = AccountStore(directory: dir, secrets: secrets, clientIds: .none)
        relaunched.migrateLegacyTokens(from: legacy)
        #expect(relaunched.accounts.count == 1)
        #expect(secrets.read(copied.id)?.accessToken == "new-pat")
    }

    // MARK: Validation results

    @Test("A validation fills identity, scopes, expiry, status and the check time")
    func appliesValidation() throws {
        let store = AccountStore(directory: Self.tempDir(), secrets: InMemoryAccountSecretStore(), clientIds: .none)
        let account = HostingAccount(instanceId: HostingInstance.gitLabDotCom.id, method: .personalToken, status: .unverified)
        try store.addAccount(account, secret: AccountSecret(accessToken: "pat"))
        var expiring = Self.tanuki
        expiring.expiresAt = Self.now + 3 * Self.day
        store.applyValidation(expiring, to: account.id, now: Self.now)
        let saved = store.accounts[0]
        #expect(saved.login == "tanuki-test")
        #expect(saved.avatarURL == URL(string: "https://gitlab.example.test/a.png"))
        #expect(saved.scopes == ["api"])
        #expect(saved.expiresAt == Self.now + 3 * Self.day)
        #expect(saved.status == .expiringSoon)
        #expect(saved.lastValidatedAt == Self.now)
    }

    @Test("Unreported scopes: an OAuth account keeps its granted ones, a token account has none")
    func validationWithoutScopes() throws {
        let store = AccountStore(directory: Self.tempDir(), secrets: InMemoryAccountSecretStore(), clientIds: .none)
        let oauth = HostingAccount(instanceId: HostingInstance.gitLabDotCom.id, method: .oauth, scopes: ["api"])
        let token = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, method: .personalToken, scopes: ["repo"])
        try store.addAccount(oauth, secret: AccountSecret(accessToken: "a"))
        try store.addAccount(token, secret: AccountSecret(accessToken: "b"))
        var unreported = Self.tanuki
        unreported.scopes = nil
        store.applyValidation(unreported, to: oauth.id, now: Self.now)
        store.applyValidation(unreported, to: token.id, now: Self.now)
        #expect(store.accounts.first { $0.id == oauth.id }?.scopes == ["api"])
        #expect(store.accounts.first { $0.id == token.id }?.scopes == [])
    }

    @Test("needsAttention keeps the reason and, when given, the check time")
    func marksNeedsAttention() throws {
        let store = AccountStore(directory: Self.tempDir(), secrets: InMemoryAccountSecretStore(), clientIds: .none)
        let account = HostingAccount(instanceId: HostingInstance.gitLabDotCom.id, method: .oauth, status: .ok)
        try store.addAccount(account, secret: AccountSecret(accessToken: "a"))
        store.markNeedsAttention(account.id, .expired)
        #expect(store.accounts[0].status == .needsAttention(.expired))
        #expect(store.accounts[0].lastValidatedAt == nil)
        store.markNeedsAttention(account.id, .revoked, validatedAt: Self.now)
        #expect(store.accounts[0].status == .needsAttention(.revoked))
        #expect(store.accounts[0].lastValidatedAt == Self.now)
    }

    // MARK: Sync of rotated old tokens

    @Test("An old token changed in Remote hosts sends its account back to unverified")
    func rotatedLegacyToken() throws {
        let secrets = InMemoryAccountSecretStore()
        let store = AccountStore(directory: Self.tempDir(), secrets: secrets, clientIds: .none)
        store.migrateLegacyTokens(from: Legacy(tokens: ["gitlab.com": "pat-1"]))
        let copied = try #require(store.accounts.first)
        store.applyValidation(Self.tanuki, to: copied.id, now: Self.now)

        store.migrateLegacyTokens(from: Legacy(tokens: ["gitlab.com": "pat-2"]))
        #expect(secrets.read(copied.id)?.accessToken == "pat-2")
        #expect(store.accounts[0].status == .unverified)
        #expect(store.accounts[0].lastValidatedAt == nil)
    }
}
