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

    private func setup(refresh: @escaping @Sendable (String) async throws -> TokenGrant = { _ in throw HostingAuthError.refreshRejected },
                       chooseAccount: (@Sendable (AmbiguousRemote) async -> RepoAccountChoice?)? = nil) -> Setup {
        let secrets = InMemoryAccountSecretStore()
        let dir = TemporaryDirectories.make("gitForge-prauth")
        let store = AccountStore(directory: dir, secrets: secrets, clientIds: OAuthClientIDs(gitHub: "gh", gitLab: "gl"))
        let client = FakeAuthClient(refresh: refresh)
        let refresher = TokenRefresher(secrets: secrets, makeClient: { _ in client },
                                       onRefreshRejected: { id in await store.markNeedsAttention(id, .expired) })
        let auth = AccountPullRequestAuth(store: store, refresher: refresher, chooseAccount: chooseAccount)
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
        let s = setup()
        try add(s.store, login: "octo", secret: AccountSecret(accessToken: "test-oauth"))
        #expect(await s.auth.access(host: Self.github, repoPath: "/r/app") == .token("test-oauth"))
    }

    @Test("No usable account: connect on that instance, reconnecting its only failing account")
    func fallbacks() async throws {
        let failing = setup()
        let dead = try add(failing.store, .gitLabDotCom, login: "old", status: .needsAttention(.revoked),
                           secret: AccountSecret(accessToken: "test-dead"))
        #expect(await failing.auth.access(host: Self.gitlab, repoPath: "/r/app")
                == .connectAccount(instanceId: HostingInstance.gitLabDotCom.id, replacing: dead.id))
        let none = setup()
        #expect(await none.auth.access(host: Self.github, repoPath: "/r/app")
                == .connectAccount(instanceId: HostingInstance.gitHubDotCom.id, replacing: nil))
    }

    @Test("System credentials chosen for git: Pull requests uses the automatic account, and the choice stays")
    func systemChoice() async throws {
        let s = setup()
        try add(s.store, login: "octo", secret: AccountSecret(accessToken: "test-oauth"))
        s.store.setChoice(.system, repoPath: "/r/app", remoteName: "origin")
        #expect(await s.auth.access(host: Self.github, repoPath: "/r/app") == .token("test-oauth"))
        #expect(s.store.choice(repoPath: "/r/app", remoteName: "origin") == .system)
    }

    @Test("System chosen and two accounts: asks, uses the answer, and doesn't store it")
    func systemChoiceAmbiguous() async throws {
        let s = setup(chooseAccount: { remote in .account(remote.candidates[1].id) })
        try add(s.store, login: "octo", secret: AccountSecret(accessToken: "test-a"))
        try add(s.store, login: "work", secret: AccountSecret(accessToken: "test-b"))
        s.store.setChoice(.system, repoPath: "/r/app", remoteName: "origin")
        let host = RemoteHost(provider: .github, host: "github.com", owner: "acme", repo: "app")
        let result = await s.auth.access(host: host, repoPath: "/r/app")
        #expect(result == .token("test-a") || result == .token("test-b"))
        #expect(s.store.choice(repoPath: "/r/app", remoteName: "origin") == .system)
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

    @Test("By account id: a usable account gives its token, without a repo")
    func accountIdToken() async throws {
        let s = setup()
        let account = try add(s.store, login: "octo", secret: AccountSecret(accessToken: "test-oauth"))
        #expect(await s.auth.access(accountId: account.id) == .token("test-oauth"))
    }

    @Test("By account id: an account that needs attention, or one that's gone, offers to connect")
    func accountIdUnusable() async throws {
        let s = setup()
        let dead = try add(s.store, .gitLabDotCom, login: "old", status: .needsAttention(.revoked),
                           secret: AccountSecret(accessToken: "test-dead"))
        #expect(await s.auth.access(accountId: dead.id)
                == .connectAccount(instanceId: HostingInstance.gitLabDotCom.id, replacing: dead.id))
        #expect(await s.auth.access(accountId: UUID()) == .connectAccount(instanceId: nil, replacing: nil))
    }

    @Test("By account id: a rejected token is refreshed once, as for a repo")
    func accountIdRejected() async throws {
        let refreshes = LockedList<String>()
        let s = setup(refresh: { refreshToken in
            refreshes.append(refreshToken)
            return TokenGrant(accessToken: "test-new", refreshToken: "r2", expiresIn: 7200, scopes: nil)
        })
        let account = try add(s.store, .gitLabDotCom, login: "tanuki",
                              secret: AccountSecret(accessToken: "test-old", refreshToken: "r1",
                                                    accessTokenExpiresAt: Date().addingTimeInterval(3600)))
        #expect(await s.auth.access(accountId: account.id, rejected: "test-old") == .token("test-new"))
        #expect(refreshes.values == ["r1"])

        let plain = setup()
        let github = try add(plain.store, login: "octo", secret: AccountSecret(accessToken: "test-oauth"))
        #expect(await plain.auth.access(accountId: github.id, rejected: "test-oauth")
                == .connectAccount(instanceId: HostingInstance.gitHubDotCom.id, replacing: github.id))
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

    @Test("Two accounts in a background lookup (History's CI line): no question, no stored choice")
    func ambiguousNonInteractive() async throws {
        let asked = LockedList<String>()
        let s = setup(chooseAccount: { remote in asked.append(remote.host); return nil })
        try add(s.store, login: "first", secret: AccountSecret(accessToken: "a"))
        try add(s.store, login: "second", secret: AccountSecret(accessToken: "b"))
        #expect(await s.auth.access(host: Self.github, repoPath: "/r/app", interactive: false) == .cancelled)
        #expect(asked.values.isEmpty)
        #expect(s.store.choice(repoPath: "/r/app", remoteName: "origin") == nil)
    }
}
