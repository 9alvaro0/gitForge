import Foundation
import Testing
@testable import gitForge

@Suite("AccountPullRequestAuth", .serialized)
@MainActor
struct AccountPullRequestAuthTests {
    nonisolated static let github = RemoteHost(provider: .github, host: "github.com", owner: "octo", repo: "app")
    nonisolated static let gitlab = RemoteHost(provider: .gitlab, host: "gitlab.com", owner: "group", repo: "app")

    private struct Setup {
        let store: AccountStore
        let auth: AccountPullRequestAuth
    }

    private func setup(legacy: [String: String] = [:],
                       refresh: @escaping @Sendable (String) async throws -> TokenGrant = { _ in throw HostingAuthError.refreshRejected },
                       chooseAccount: (@Sendable (AmbiguousRemote) async -> RepoAccountChoice?)? = nil) -> Setup {
        let secrets = InMemoryAccountSecretStore()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-prauth-\(UUID().uuidString)")
        let store = AccountStore(directory: dir, secrets: secrets, clientIds: OAuthClientIDs(gitHub: "gh", gitLab: "gl"))
        let client = FakeAuthClient(refresh: refresh)
        let refresher = TokenRefresher(secrets: secrets, makeClient: { _ in client },
                                       onRefreshRejected: { id in await store.markNeedsAttention(id, .expired) })
        let auth = AccountPullRequestAuth(store: store, refresher: refresher, chooseAccount: chooseAccount,
                                          legacyToken: { legacy[$0] })
        return Setup(store: store, auth: auth)
    }

    @discardableResult
    private func add(_ store: AccountStore, _ instance: HostingInstance = .gitHubDotCom, login: String,
                     status: HostingAccount.Status = .ok, secret: AccountSecret) throws -> HostingAccount {
        let account = HostingAccount(instanceId: instance.id, login: login, method: .oauth, status: status)
        try store.addAccount(account, secret: secret)
        return account
    }

    @Test("The repo's account gives the token")
    func accountToken() async throws {
        let s = setup(legacy: ["github.com": "test-legacy"])
        try add(s.store, login: "octo", secret: AccountSecret(accessToken: "test-oauth"))
        #expect(await s.auth.access(host: Self.github, repoPath: "/r/app") == .token("test-oauth"))
    }

    @Test("No usable account: the old token; none at all: connect on that instance")
    func fallbacks() async throws {
        let withLegacy = setup(legacy: ["gitlab.com": "test-legacy"])
        try add(withLegacy.store, .gitLabDotCom, login: "old", status: .needsAttention(.revoked), secret: AccountSecret(accessToken: "dead"))
        #expect(await withLegacy.auth.access(host: Self.gitlab, repoPath: "/r/app") == .token("test-legacy"))
        let none = setup()
        #expect(await none.auth.access(host: Self.github, repoPath: "/r/app")
                == .connectAccount(instanceId: HostingInstance.gitHubDotCom.id, replacing: nil))
    }

    @Test("System credentials chosen for the repo: the old token, never the account")
    func systemChoice() async throws {
        let s = setup(legacy: ["github.com": "test-legacy"])
        try add(s.store, login: "octo", secret: AccountSecret(accessToken: "test-oauth"))
        s.store.setChoice(.system, repoPath: "/r/app", remoteName: "origin")
        #expect(await s.auth.access(host: Self.github, repoPath: "/r/app") == .token("test-legacy"))
    }

    @Test("A rejected old token offers to connect an account")
    func rejectedLegacy() async {
        let s = setup(legacy: ["gitlab.com": "test-legacy"])
        #expect(await s.auth.access(host: Self.gitlab, repoPath: "/r/app", rejected: "test-legacy")
                == .connectAccount(instanceId: HostingInstance.gitLabDotCom.id, replacing: nil))
    }

    @Test("A rejected account token: GitLab OAuth refreshes; a token that can't is revoked and offered for reconnect")
    func rejectedAccount() async throws {
        let refreshing = setup(refresh: { _ in TokenGrant(accessToken: "test-new", refreshToken: "r2", expiresIn: 7200, scopes: nil) })
        try add(refreshing.store, .gitLabDotCom, login: "tanuki",
                secret: AccountSecret(accessToken: "test-old", refreshToken: "r1", accessTokenExpiresAt: Date().addingTimeInterval(3600)))
        #expect(await refreshing.auth.access(host: Self.gitlab, repoPath: "/r/app", rejected: "test-old") == .token("test-new"))

        let plain = setup()
        let account = try add(plain.store, login: "octo", secret: AccountSecret(accessToken: "test-oauth"))
        #expect(await plain.auth.access(host: Self.github, repoPath: "/r/app", rejected: "test-oauth")
                == .connectAccount(instanceId: HostingInstance.gitHubDotCom.id, replacing: account.id))
        #expect(plain.store.accounts[0].status == .needsAttention(.revoked))
    }

    @Test("Offline while refreshing: a failure to show, not Connect")
    func refreshOffline() async throws {
        let s = setup(refresh: { _ in throw HostingAuthError.network("offline") })
        try add(s.store, .gitLabDotCom, login: "tanuki",
                secret: AccountSecret(accessToken: "test-old", refreshToken: "r1", accessTokenExpiresAt: Date().addingTimeInterval(60)))
        guard case .failed(let message) = await s.auth.access(host: Self.gitlab, repoPath: "/r/app") else {
            Issue.record("expected failed"); return
        }
        #expect(message.contains("offline"))
    }

    @Test("Only a failing account on the instance: Connect offers to reconnect that one")
    func reconnectFailingCopy() async throws {
        let s = setup()
        let copied = try add(s.store, .gitLabDotCom, login: "old", status: .needsAttention(.revoked), secret: AccountSecret(accessToken: "dead"))
        #expect(await s.auth.access(host: Self.gitlab, repoPath: "/r/app")
                == .connectAccount(instanceId: HostingInstance.gitLabDotCom.id, replacing: copied.id))
    }

    @Test("Two accounts: asks; the choice is used and remembered; Cancel is cancelled")
    func ambiguous() async throws {
        let picked = LockedList<UUID>()
        let s = setup(chooseAccount: { remote in picked.values.first.map(RepoAccountChoice.account) })
        try add(s.store, login: "first", secret: AccountSecret(accessToken: "test-first"))
        let second = try add(s.store, login: "second", secret: AccountSecret(accessToken: "test-second"))
        picked.append(second.id)
        #expect(await s.auth.access(host: Self.github, repoPath: "/r/app") == .token("test-second"))
        #expect(s.store.choice(repoPath: "/r/app", remoteName: "origin") == .account(second.id))

        let cancelling = setup(chooseAccount: { _ in nil })
        try add(cancelling.store, login: "first", secret: AccountSecret(accessToken: "a"))
        try add(cancelling.store, login: "second", secret: AccountSecret(accessToken: "b"))
        #expect(await cancelling.auth.access(host: Self.github, repoPath: "/r/app") == .cancelled)
    }
}
