import Foundation
import Testing
@testable import gitForge

@Suite("Clone › My repos on accounts", .serialized)
@MainActor
struct RemoteRepoListModelTests {

    private struct Setup {
        let store: AccountStore
        let secrets: InMemoryAccountSecretStore
        let server: StubServer
    }

    private func setup() -> Setup {
        let secrets = InMemoryAccountSecretStore()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-repos-\(UUID().uuidString)")
        let store = AccountStore(directory: dir, secrets: secrets, clientIds: OAuthClientIDs(gitHub: "gh", gitLab: "gl"))
        return Setup(store: store, secrets: secrets, server: StubServer())
    }

    private func model(_ s: Setup, kind: HostingInstance.Kind = .github,
                       refresh: @escaping @Sendable (String) async throws -> TokenGrant = { _ in throw HostingAuthError.refreshRejected })
        -> RemoteRepoListModel {
        let client = FakeAuthClient(refresh: refresh)
        let store = s.store
        let refresher = TokenRefresher(secrets: s.secrets, makeClient: { _ in client },
                                       onRefreshRejected: { id in await store.markNeedsAttention(id, .expired) })
        return RemoteRepoListModel(kind: kind, store: s.store, refresher: refresher,
                                   browser: RemoteRepoBrowserFactory.make(for: kind, session: s.server.http.session))
    }

    /// An instance served by the stub server.
    private func instance(_ s: Setup, kind: HostingInstance.Kind = .github) throws -> HostingInstance {
        let instance = HostingInstance(kind: kind, host: s.server.host, oauthClientId: "client")
        try s.store.addInstance(instance)
        return instance
    }

    @discardableResult
    private func account(_ s: Setup, _ instance: HostingInstance, login: String?, method: HostingAccount.Method = .oauth,
                         status: HostingAccount.Status = .ok, secret: AccountSecret) throws -> HostingAccount {
        let account = HostingAccount(instanceId: instance.id, login: login, method: method, status: status)
        try s.store.addAccount(account, secret: secret)
        return account
    }

    private static func githubPage(_ count: Int, from start: Int) -> Data {
        let items = (start..<start + count).map { i in
            #"{"id":\#(i),"name":"r\#(i)","full_name":"octo/r\#(i)","description":null,"private":false,"ssh_url":null,"clone_url":"https://github.com/octo/r\#(i).git","default_branch":"main"}"#
        }
        return Data("[\(items.joined(separator: ","))]".utf8)
    }

    @Test("No usable account: connect on the built-in instance; only a failing one: reconnect it")
    func needsAccount() throws {
        let empty = setup()
        #expect(model(empty).state == .needsAccount(instanceId: HostingInstance.gitHubDotCom.id, replacing: nil))

        let failing = setup()
        let dead = try account(failing, .gitLabDotCom, login: nil, method: .personalToken,
                               status: .needsAttention(.revoked), secret: AccountSecret(accessToken: "test-dead"))
        let m = model(failing, kind: .gitlab)
        #expect(m.accounts.isEmpty)
        #expect(m.state == .needsAccount(instanceId: HostingInstance.gitLabDotCom.id, replacing: dead.id))
    }

    @Test("Lists the selected account's repos through its instance; another account can be picked")
    func listsAndSwitches() async throws {
        let s = setup()
        let instance = try instance(s)
        let octo = try account(s, instance, login: "octo", secret: AccountSecret(accessToken: "test-a"))
        let work = try account(s, instance, login: "work", secret: AccountSecret(accessToken: "test-b"))
        s.server.on("GET", "/api/v3/user/repos", fixture: "github-repos")
        let m = model(s)
        #expect(m.accounts.map(\.login) == ["octo", "work"])
        #expect(m.selectedAccountId == octo.id)
        #expect(m.label(for: octo) == "octo @ \(s.server.host)")

        await m.load()
        #expect(m.state == .loaded)
        #expect(m.repos.map(\.fullName) == ["octo/app"])
        #expect(!m.hasMore)

        m.select(work.id)
        #expect(m.repos.isEmpty)
        await m.load()
        let auths = s.server.requests("GET", "/api/v3/user/repos").map { $0.header("Authorization") }
        #expect(auths == ["Bearer test-a", "Bearer test-b"])
    }

    @Test("A load outlives a cancelled caller (the view's task restarting), so it doesn't fail as cancelled")
    func outlivesCaller() async throws {
        let s = setup()
        let instance = try instance(s)
        try account(s, instance, login: "octo", secret: AccountSecret(accessToken: "test-a"))
        s.server.on("GET", "/api/v3/user/repos", fixture: "github-repos")
        let m = model(s)
        let caller = Task { await m.load() }
        caller.cancel()
        await caller.value
        #expect(m.state == .loaded)
        #expect(m.repos.map(\.fullName) == ["octo/app"])
    }

    @Test("A full page offers more; Load more appends the next one")
    func pages() async throws {
        let s = setup()
        let instance = try instance(s)
        try account(s, instance, login: "octo", secret: AccountSecret(accessToken: "test-a"))
        s.server.on("GET", "/api/v3/user/repos", body: Self.githubPage(50, from: 0))
        s.server.on("GET", "/api/v3/user/repos", body: Self.githubPage(1, from: 50))
        let m = model(s)
        await m.load()
        #expect(m.repos.count == 50)
        #expect(m.hasMore)
        await m.loadMore()
        #expect(m.repos.count == 51)
        #expect(!m.hasMore)
        m.search = "r50"
        #expect(m.filtered.map(\.fullName) == ["octo/r50"])
    }

    @Test("Rejected: GitLab OAuth refreshes and retries once; a token that can't is marked and offered for reconnect")
    func rejected() async throws {
        let gitlab = setup()
        let lab = try instance(gitlab, kind: .gitlab)
        try account(gitlab, lab, login: "group-dev",
                    secret: AccountSecret(accessToken: "test-old", refreshToken: "test-refresh",
                                          accessTokenExpiresAt: Date().addingTimeInterval(3600)))
        gitlab.server.on("GET", "/api/v4/projects", status: 401, body: Data("{}".utf8))
        gitlab.server.on("GET", "/api/v4/projects", fixture: "gitlab-projects")
        let refreshing = model(gitlab, kind: .gitlab,
                               refresh: { _ in TokenGrant(accessToken: "test-new", refreshToken: "test-refresh-2",
                                                          expiresIn: 7200, scopes: nil) })
        await refreshing.load()
        #expect(refreshing.state == .loaded)
        #expect(gitlab.server.requests("GET", "/api/v4/projects").map { $0.header("Authorization") }
                == ["Bearer test-old", "Bearer test-new"])

        let pat = setup()
        let hub = try instance(pat)
        let token = try account(pat, hub, login: "octo", method: .personalToken, secret: AccountSecret(accessToken: "test-pat"))
        pat.server.on("GET", "/api/v3/user/repos", status: 401, body: Data("{}".utf8))
        let m = model(pat)
        await m.load()
        #expect(m.state == .needsAccount(instanceId: hub.id, replacing: token.id))
        #expect(pat.store.accounts.first?.status == .needsAttention(.revoked))
    }

    @Test("Reconnected in place after a rejection: the list asks to load again")
    func reconnectReloads() async throws {
        let s = setup()
        let hub = try instance(s)
        let token = try account(s, hub, login: "octo", method: .personalToken, secret: AccountSecret(accessToken: "test-pat"))
        s.server.on("GET", "/api/v3/user/repos", status: 401, body: Data("{}".utf8))
        s.server.on("GET", "/api/v3/user/repos", fixture: "github-repos")
        let m = model(s)
        await m.load()
        let before = m.loadRequest
        #expect(m.state == .needsAccount(instanceId: hub.id, replacing: token.id))

        // "Reconnect" keeps the account id and gives it a working token.
        try s.secrets.write(AccountSecret(accessToken: "test-new"), for: token.id)
        var reconnected = try #require(s.store.accounts.first)
        reconnected.status = .ok
        s.store.updateAccount(reconnected)
        m.refreshAccounts()
        #expect(m.state == .idle)
        #expect(m.loadRequest != before)
        await m.load()
        #expect(m.state == .loaded)
    }

    @Test("Other failures are shown as errors, and the account stays as it was")
    func forbidden() async throws {
        let s = setup()
        let instance = try instance(s)
        try account(s, instance, login: "octo", secret: AccountSecret(accessToken: "test-a"))
        s.server.on("GET", "/api/v3/user/repos", status: 403, body: Data("{}".utf8))
        let m = model(s)
        await m.load()
        guard case .failed(let message) = m.state else {
            Issue.record("expected a failure, got \(m.state)")
            return
        }
        #expect(!message.isEmpty)
        #expect(s.store.accounts.first?.status == .ok)
    }
}
