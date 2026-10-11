import Foundation
import Testing
@testable import gitForge

@Suite("GitHubAuthClient")
struct GitHubAuthClientTests {
    let server = StubServer()
    var client: GitHubAuthClient {
        GitHubAuthClient(instance: HostingInstance(kind: .github, host: server.host), http: server.http)
    }

    @Test("Asks for a device code with the client id and the required scopes")
    func deviceCode() async throws {
        server.on("POST", "/login/device/code", fixture: "oauth-device-code-github")
        let code = try await client.requestDeviceCode(clientId: "test-client")
        #expect(code.userCode == "WDJB-MJHT")
        #expect(code.verificationURI.absoluteString == "https://github.com/login/device")
        #expect(code.interval == 5)
        let request = try #require(server.requests("POST", "/login/device/code").first)
        #expect(request.form == ["client_id": "test-client", "scope": "repo read:org workflow"])
        #expect(request.header("Accept") == "application/json")
    }

    @Test("An OAuth app without device flow says to use a token")
    func deviceFlowDisabled() async {
        server.on("POST", "/login/device/code", status: 400, fixture: "oauth-device-flow-disabled")
        await #expect(throws: HostingAuthError.deviceFlowUnsupported) {
            try await client.requestDeviceCode(clientId: "test-client")
        }
    }

    @Test("Polling over HTTP: pending, slow_down, then the token")
    func pollsUntilGranted() async throws {
        server.on("POST", "/login/oauth/access_token", fixture: "oauth-pending")
        server.on("POST", "/login/oauth/access_token", fixture: "oauth-slow-down")
        server.on("POST", "/login/oauth/access_token", fixture: "github-token-granted")
        let code = DeviceCode(deviceCode: "test-device-code", userCode: "U", verificationURI: URL(string: "https://github.com/login/device")!,
                              verificationURIComplete: nil, expiresIn: 900, interval: 5)
        let clock = VirtualClock()
        let grant = try await client.pollToken(clientId: "test-client", code: code, clock: clock.clock)
        #expect(grant.accessToken == "test-github-access")
        #expect(grant.scopes == ["repo", "read:org", "workflow"])
        #expect(clock.sleeps == [5, 5, 10])
        let polls = server.requests("POST", "/login/oauth/access_token")
        #expect(polls.count == 3)
        #expect(polls.first?.form == ["client_id": "test-client", "device_code": "test-device-code",
                                      "grant_type": "urn:ietf:params:oauth:grant-type:device_code"])
    }

    @Test("A classic token: user, scopes from X-OAuth-Scopes, bearer header")
    func validatesClassic() async throws {
        server.on("GET", "/api/v3/user", headers: ["X-OAuth-Scopes": "repo, read:org, workflow, gist"], fixture: "github-user")
        let validation = try await client.validate(token: "test-token", method: .personalToken)
        #expect(validation.user == HostingUser(login: "octo-test", displayName: "Octo Test",
                                               avatarURL: URL(string: "https://avatars.example.test/u/1")))
        #expect(validation.scopes == ["repo", "read:org", "workflow", "gist"])
        #expect(validation.expiresAt == nil)
        #expect(server.requests("GET", "/api/v3/user").first?.header("Authorization") == "Bearer test-token")
    }

    @Test("A fine-grained token (no scopes header) is accepted with scopes not verifiable")
    func fineGrained() async throws {
        server.on("GET", "/api/v3/user", fixture: "github-user")
        let validation = try await client.validate(token: "test-token", method: .personalToken)
        #expect(validation.scopes == nil)
        #expect(validation.user.login == "octo-test")
    }

    @Test("A token without workflow comes back with its user and the scopes it has")
    func missingWorkflow() async throws {
        server.on("GET", "/api/v3/user", headers: ["X-OAuth-Scopes": "repo, read:org"], fixture: "github-user")
        let validation = try await client.validate(token: "test-token", method: .personalToken)
        #expect(validation.user.login == "octo-test")
        #expect(validation.scopes == ["repo", "read:org"])
        #expect(validation.missingScopes(kind: .github) == ["workflow"])
    }

    @Test("An empty scopes header is a token with no scopes, not a fine-grained one")
    func emptyScopesHeader() async throws {
        server.on("GET", "/api/v3/user", headers: ["X-OAuth-Scopes": ""], fixture: "github-user")
        let validation = try await client.validate(token: "test-token", method: .personalToken)
        #expect(validation.scopes == [])
        #expect(validation.missingScopes(kind: .github) == ["repo", "read:org", "workflow"])
    }

    @Test("The token's expiry comes from github-authentication-token-expiration")
    func expiry() async throws {
        server.on("GET", "/api/v3/user", headers: ["github-authentication-token-expiration": "2026-10-14 12:00:00 UTC"],
                  fixture: "github-user")
        let validation = try await client.validate(token: "test-token", method: .personalToken)
        #expect(validation.expiresAt == ISO8601DateFormatter().date(from: "2026-10-14T12:00:00Z"))
        #expect(GitHubAuthClient.parseExpiration("2026-10-14 14:00:00 +0200") == ISO8601DateFormatter().date(from: "2026-10-14T12:00:00Z"))
    }

    @Test("A rejected token is unauthorized")
    func unauthorized() async {
        server.on("GET", "/api/v3/user", status: 401, body: Data(#"{"message":"Bad credentials"}"#.utf8))
        await #expect(throws: HostingAuthError.unauthorized) {
            try await client.validate(token: "test-token", method: .personalToken)
        }
    }

    @Test("GitHub tokens don't refresh, and no request is made")
    func noRefresh() async {
        await #expect(throws: HostingAuthError.refreshRejected) {
            try await client.refresh(clientId: "test-client", refreshToken: "r")
        }
        #expect(server.requests.isEmpty)
    }
}
