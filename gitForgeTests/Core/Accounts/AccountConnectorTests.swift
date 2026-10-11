import Foundation
import Testing
@testable import gitForge

@Suite("Connecting accounts", .serialized)
@MainActor
struct AccountConnectorTests {
    nonisolated static let user = HostingUser(login: "octo-test", displayName: "Octo Test", avatarURL: nil)

    private func makeStore(_ secrets: InMemoryAccountSecretStore = .init()) -> AccountStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-connector-\(UUID().uuidString)")
        return AccountStore(directory: dir, secrets: secrets, clientIds: .none)
    }

    private func waiting(_ flow: DeviceFlowSession) -> Bool {
        if case .waitingForUser = flow.state { true } else { false }
    }

    private func finished(_ flow: DeviceFlowSession) -> Bool {
        switch flow.state {
        case .connected, .failed, .cancelled: true
        default: false
        }
    }

    /// A self-hosted instance served by `server`, with an OAuth client id.
    private func stubbed(_ kind: HostingInstance.Kind, secrets: InMemoryAccountSecretStore = .init())
        throws -> (StubServer, AccountStore, AccountConnector, HostingInstance) {
        let server = StubServer()
        let store = makeStore(secrets)
        let instance = HostingInstance(kind: kind, host: server.host, oauthClientId: "test-client")
        try store.addInstance(instance)
        let connector = AccountConnector(store: store, makeClient: { HostingAuthClients.make(for: $0, http: server.http) },
                                         clock: .fast)
        return (server, store, connector, instance)
    }

    // MARK: Token

    @Test("A valid token is saved trimmed, as a verified token account")
    func connectsToken() async throws {
        let secrets = InMemoryAccountSecretStore()
        let store = makeStore(secrets)
        let client = FakeAuthClient(instance: .gitHubDotCom,
                                    validate: { _ in TokenValidation(user: Self.user, scopes: ["repo", "read:org", "workflow"], expiresAt: nil) })
        let connector = AccountConnector(store: store, makeClient: { _ in client })
        let result = try await connector.connect(token: "  test-token\n", on: .gitHubDotCom)
        #expect(result.scopesVerified)
        #expect(result.account.method == .personalToken)
        #expect(result.account.login == "octo-test")
        #expect(store.accounts == [result.account])
        #expect(secrets.read(result.account.id)?.accessToken == "test-token")
        #expect(client.validatedTokens == ["test-token"])
    }

    @Test("A token missing scopes is refused with the list, and nothing is saved")
    func refusesMissingScopes() async {
        let store = makeStore()
        let connector = AccountConnector(store: store, makeClient: { _ in
            FakeAuthClient(instance: .gitHubDotCom,
                           validate: { _ in TokenValidation(user: Self.user, scopes: ["repo", "read:org"], expiresAt: nil) })
        })
        await #expect(throws: HostingAuthError.missingScopes(["workflow"])) {
            try await connector.connect(token: "test-token", on: .gitHubDotCom)
        }
        #expect(store.accounts.isEmpty)
    }

    @Test("Reconnecting a copied account that has no login updates it instead of adding another")
    func reconnectReplaces() async throws {
        let secrets = InMemoryAccountSecretStore()
        let store = makeStore(secrets)
        let copied = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, method: .personalToken,
                                    status: .needsAttention(.revoked))
        try store.addAccount(copied, secret: AccountSecret(accessToken: "dead"))
        let connector = AccountConnector(store: store, makeClient: { _ in
            FakeAuthClient(instance: .gitHubDotCom,
                           validate: { _ in TokenValidation(user: Self.user, scopes: ["repo", "read:org", "workflow"], expiresAt: nil) })
        })
        let result = try await connector.connect(token: "test-token", on: .gitHubDotCom, replacing: copied.id)
        #expect(result.account.id == copied.id)
        #expect(store.accounts.count == 1)
        #expect(store.accounts[0].login == "octo-test")
        #expect(store.accounts[0].status == .ok)
        #expect(secrets.read(copied.id)?.accessToken == "test-token")
    }

    @Test("A fine-grained token is saved with scopes not verifiable")
    func fineGrained() async throws {
        let store = makeStore()
        let connector = AccountConnector(store: store, makeClient: { _ in
            FakeAuthClient(validate: { _ in TokenValidation(user: Self.user, scopes: nil, expiresAt: nil) })
        })
        let result = try await connector.connect(token: "test-token", on: .gitHubDotCom)
        #expect(!result.scopesVerified)
        #expect(result.account.scopes == [])
    }

    @Test("An empty token or a Keychain failure saves nothing")
    func failures() async {
        let secrets = InMemoryAccountSecretStore()
        secrets.failWrites = true
        let store = makeStore(secrets)
        let connector = AccountConnector(store: store, makeClient: { _ in
            FakeAuthClient(validate: { _ in TokenValidation(user: Self.user, scopes: ["repo", "read:org", "workflow"], expiresAt: nil) })
        })
        await #expect(throws: HostingAuthError.unauthorized) {
            try await connector.connect(token: "   ", on: .gitHubDotCom)
        }
        let error = await #expect(throws: HostingAuthError.self) {
            try await connector.connect(token: "test-token", on: .gitHubDotCom)
        }
        if case .storage = error {} else { Issue.record("Expected a storage error, got \(String(describing: error))") }
        #expect(store.accounts.isEmpty)
    }

    @Test("Without a client id there's no OAuth, only tokens")
    func noClientId() {
        let connector = AccountConnector(store: makeStore())
        #expect(!connector.supportsOAuth(.gitHubDotCom))
        #expect(connector.deviceFlow(on: .gitHubDotCom) == nil)
        #expect(connector.supportsOAuth(HostingInstance(kind: .gitlab, host: "git.empresa.com", oauthClientId: "id")))
    }

    // MARK: Device flow

    @Test("Device flow: the code is shown, then the approved account is saved as OAuth")
    func deviceFlowConnects() async throws {
        let secrets = InMemoryAccountSecretStore()
        let (server, store, connector, instance) = try stubbed(.github, secrets: secrets)
        server.on("POST", "/login/device/code", fixture: "oauth-device-code-github")
        server.on("POST", "/login/oauth/access_token", fixture: "oauth-pending")
        server.on("GET", "/api/v3/user", headers: ["X-OAuth-Scopes": "repo, read:org, workflow"], fixture: "github-user")
        let flow = try #require(connector.deviceFlow(on: instance))
        #expect(flow.state == .idle)

        flow.start()
        await waitUntil { waiting(flow) }
        guard case .waitingForUser(let code, _) = flow.state else {
            Issue.record("Expected waitingForUser, got \(flow.state)")
            return
        }
        #expect(code.userCode == "WDJB-MJHT")
        #expect(store.accounts.isEmpty)

        server.on("POST", "/login/oauth/access_token", fixture: "github-token-granted")
        await waitUntil { finished(flow) }
        guard case .connected(let account) = flow.state else {
            Issue.record("Expected connected, got \(flow.state)")
            return
        }
        #expect(account.login == "octo-test")
        #expect(account.method == .oauth)
        #expect(account.scopes == ["repo", "read:org", "workflow"])
        #expect(store.accounts.map(\.id) == [account.id])
        #expect(secrets.read(account.id)?.accessToken == "test-github-access")
        #expect(!flow.isRunning)
    }

    @Test("Cancelling while waiting stops polling and saves nothing")
    func deviceFlowCancel() async throws {
        let (server, store, connector, instance) = try stubbed(.github)
        server.on("POST", "/login/device/code", fixture: "oauth-device-code-github")
        server.on("POST", "/login/oauth/access_token", fixture: "oauth-pending")
        let flow = try #require(connector.deviceFlow(on: instance))
        flow.start()
        await waitUntil { waiting(flow) }
        flow.cancel()
        #expect(flow.state == .cancelled)
        #expect(!flow.isRunning)

        try await Task.sleep(for: .milliseconds(50))
        let polls = server.requests("POST", "/login/oauth/access_token").count
        try await Task.sleep(for: .milliseconds(100))
        #expect(server.requests("POST", "/login/oauth/access_token").count == polls)
        #expect(flow.state == .cancelled)
        #expect(store.accounts.isEmpty)
    }

    @Test("Declined in the browser: failed with accessDenied, nothing saved")
    func deviceFlowDenied() async throws {
        let (server, store, connector, instance) = try stubbed(.github)
        server.on("POST", "/login/device/code", fixture: "oauth-device-code-github")
        server.on("POST", "/login/oauth/access_token", fixture: "oauth-access-denied")
        let flow = try #require(connector.deviceFlow(on: instance))
        flow.start()
        await waitUntil { finished(flow) }
        #expect(flow.state == .failed(.accessDenied))
        #expect(store.accounts.isEmpty)
    }

    @Test("GitLab grant without the required scopes: failed with what's missing")
    func deviceFlowGitLabScopes() async throws {
        let (server, store, connector, instance) = try stubbed(.gitlab)
        server.on("POST", "/oauth/authorize_device", fixture: "oauth-device-code-gitlab")
        server.on("POST", "/oauth/token", fixture: "gitlab-token-granted-read-user")
        server.on("GET", "/api/v4/user", fixture: "gitlab-user")
        let flow = try #require(connector.deviceFlow(on: instance))
        flow.start()
        await waitUntil { finished(flow) }
        #expect(flow.state == .failed(.missingScopes(["api", "write_repository"])))
        #expect(store.accounts.isEmpty)
    }

    @Test("GitLab: the approved account keeps the refresh token and the access token's expiry")
    func deviceFlowGitLab() async throws {
        let secrets = InMemoryAccountSecretStore()
        let (server, _, connector, instance) = try stubbed(.gitlab, secrets: secrets)
        server.on("POST", "/oauth/authorize_device", fixture: "oauth-device-code-gitlab")
        server.on("POST", "/oauth/token", fixture: "gitlab-token-granted")
        server.on("GET", "/api/v4/user", fixture: "gitlab-user")
        let flow = try #require(connector.deviceFlow(on: instance))
        flow.start()
        await waitUntil { finished(flow) }
        guard case .connected(let account) = flow.state else {
            Issue.record("Expected connected, got \(flow.state)")
            return
        }
        #expect(account.scopes == ["api", "read_user", "write_repository"])
        #expect(account.expiresAt == nil)
        let secret = try #require(secrets.read(account.id))
        #expect(secret.refreshToken == "test-gitlab-refresh-2")
        #expect(secret.accessTokenExpiresAt != nil)
    }
}
