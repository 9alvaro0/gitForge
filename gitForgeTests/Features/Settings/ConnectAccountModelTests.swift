import Foundation
import Testing
@testable import gitForge

@Suite("ConnectAccountModel", .serialized)
@MainActor
struct ConnectAccountModelTests {
    nonisolated static let user = HostingUser(login: "octo-test", displayName: "Octo Test", avatarURL: nil)

    private func makeStore(_ secrets: InMemoryAccountSecretStore = .init(), clientIds: OAuthClientIDs = .none) -> AccountStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-connectmodel-\(UUID().uuidString)")
        return AccountStore(directory: dir, secrets: secrets, clientIds: clientIds)
    }

    @Test("Without a client id only tokens; with one the browser comes first")
    func methods() {
        let tokenOnly = ConnectAccountModel(store: makeStore(), connector: AccountConnector(store: makeStore()),
                                            instanceId: HostingInstance.gitHubDotCom.id, replacing: nil)
        #expect(tokenOnly.methods == [.token])
        #expect(tokenOnly.method == .token)
        let store = makeStore(clientIds: OAuthClientIDs(gitHub: "gh-client", gitLab: nil))
        let oauth = ConnectAccountModel(store: store, connector: AccountConnector(store: store),
                                        instanceId: HostingInstance.gitHubDotCom.id, replacing: nil)
        #expect(oauth.methods == [.browser, .token])
        #expect(oauth.method == .browser)
        oauth.instanceId = HostingInstance.gitLabDotCom.id
        #expect(oauth.method == .token)
    }

    @Test("A valid token connects; Done links the chosen profile")
    func tokenConnects() async throws {
        let store = makeStore()
        let connector = AccountConnector(store: store, makeClient: { _ in
            FakeAuthClient(instance: .gitHubDotCom, validate: { _ in
                TokenValidation(user: Self.user, scopes: ["repo", "read:org", "workflow"], expiresAt: nil) })
        })
        let model = ConnectAccountModel(store: store, connector: connector, instanceId: HostingInstance.gitHubDotCom.id, replacing: nil)
        model.token = "test-token"
        await model.connectToken()
        let account = try #require(model.result)
        #expect(account.login == "octo-test")
        #expect(!model.scopesWarning)
        let profile = UUID()
        model.profileChoice = profile
        model.finish()
        #expect(store.accounts.first?.linkedProfileId == profile)
    }

    @Test("Closing the sheet (Esc) after connecting still links the chosen profile")
    func closeKeepsProfile() async throws {
        let store = makeStore()
        let connector = AccountConnector(store: store, makeClient: { _ in
            FakeAuthClient(instance: .gitHubDotCom, validate: { _ in
                TokenValidation(user: Self.user, scopes: ["repo", "read:org", "workflow"], expiresAt: nil) })
        })
        let model = ConnectAccountModel(store: store, connector: connector, instanceId: HostingInstance.gitHubDotCom.id, replacing: nil)
        model.token = "test-token"
        await model.connectToken()
        let profile = UUID()
        model.profileChoice = profile
        model.close()
        #expect(store.accounts.first?.linkedProfileId == profile)
    }

    @Test("Missing scopes: named, nothing saved")
    func tokenMissingScopes() async {
        let store = makeStore()
        let connector = AccountConnector(store: store, makeClient: { _ in
            FakeAuthClient(instance: .gitHubDotCom, validate: { _ in
                TokenValidation(user: Self.user, scopes: ["repo", "read:org"], expiresAt: nil) })
        })
        let model = ConnectAccountModel(store: store, connector: connector, instanceId: HostingInstance.gitHubDotCom.id, replacing: nil)
        model.token = "test-token"
        await model.connectToken()
        #expect(model.result == nil)
        #expect(model.tokenState == .failed("The token is missing these scopes: workflow."))
        #expect(store.accounts.isEmpty)
    }

    @Test("Fine-grained token: saved with the warning")
    func fineGrained() async {
        let store = makeStore()
        let connector = AccountConnector(store: store, makeClient: { _ in
            FakeAuthClient(instance: .gitHubDotCom, validate: { _ in TokenValidation(user: Self.user, scopes: nil, expiresAt: nil) })
        })
        let model = ConnectAccountModel(store: store, connector: connector, instanceId: HostingInstance.gitHubDotCom.id, replacing: nil)
        model.token = "test-token"
        await model.connectToken()
        #expect(model.scopesWarning)
    }

    @Test("Reconnecting the copied account without a login keeps one account and its id and profile")
    func reconnectCopied() async throws {
        let secrets = InMemoryAccountSecretStore()
        let store = makeStore(secrets)
        let profile = UUID()
        let copied = HostingAccount(instanceId: HostingInstance.gitLabDotCom.id, method: .personalToken,
                                    status: .needsAttention(.revoked), linkedProfileId: profile)
        try store.addAccount(copied, secret: AccountSecret(accessToken: "dead"))
        let connector = AccountConnector(store: store, makeClient: { _ in
            FakeAuthClient(validate: { _ in TokenValidation(user: HostingUser(login: "tanuki", displayName: nil, avatarURL: nil),
                                                            scopes: ["api"], expiresAt: nil) })
        })
        let model = ConnectAccountModel(store: store, connector: connector, instanceId: HostingInstance.gitLabDotCom.id, replacing: copied.id)
        #expect(model.profileChoice == profile)
        model.token = "test-new-token"
        await model.connectToken()
        model.finish()
        #expect(store.accounts.map(\.id) == [copied.id])
        #expect(store.accounts[0].login == "tanuki")
        #expect(store.accounts[0].linkedProfileId == profile)
        #expect(secrets.read(copied.id)?.accessToken == "test-new-token")
    }

    @Test("Browser sign-in: approved in the browser, the account comes back; cancel stops it")
    func browser() async throws {
        let server = StubServer()
        let store = makeStore()
        let instance = HostingInstance(kind: .github, host: server.host, oauthClientId: "test-client")
        try store.addInstance(instance)
        let connector = AccountConnector(store: store, makeClient: { HostingAuthClients.make(for: $0, http: server.http) }, clock: .fast)
        server.on("POST", "/login/device/code", fixture: "oauth-device-code-github")
        server.on("POST", "/login/oauth/access_token", fixture: "github-token-granted")
        server.on("GET", "/api/v3/user", headers: ["X-OAuth-Scopes": "repo, read:org, workflow"], fixture: "github-user")
        let model = ConnectAccountModel(store: store, connector: connector, instanceId: instance.id, replacing: nil)
        model.startBrowser()
        await waitUntil { model.result != nil }
        #expect(model.result?.login == "octo-test")

        let pending = StubServer()
        try store.addInstance(HostingInstance(kind: .github, host: pending.host, oauthClientId: "test-client"))
        pending.on("POST", "/login/device/code", fixture: "oauth-device-code-github")
        pending.on("POST", "/login/oauth/access_token", fixture: "oauth-pending")
        let pendingConnector = AccountConnector(store: store, makeClient: { HostingAuthClients.make(for: $0, http: pending.http) }, clock: .fast)
        let second = ConnectAccountModel(store: store, connector: pendingConnector,
                                         instanceId: store.instance(forHost: pending.host)?.id, replacing: nil)
        second.startBrowser()
        await waitUntil { if case .waitingForUser = second.deviceFlow?.state { true } else { false } }
        second.cancel()
        #expect(second.deviceFlow?.state == .cancelled)
    }
}
