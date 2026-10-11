import Foundation
import Testing
@testable import gitForge

@Suite("GitLabAuthClient")
struct GitLabAuthClientTests {
    let server = StubServer()
    var client: GitLabAuthClient {
        GitLabAuthClient(instance: HostingInstance(kind: .gitlab, host: server.host), http: server.http)
    }

    @Test("Asks for a device code at /oauth/authorize_device with the required scopes")
    func deviceCode() async throws {
        server.on("POST", "/oauth/authorize_device", fixture: "oauth-device-code-gitlab")
        let code = try await client.requestDeviceCode(clientId: "test-client")
        #expect(code.userCode == "0A44L90H")
        #expect(code.verificationURIComplete?.absoluteString == "https://gitlab.com/oauth/device?user_code=0A44L90H")
        #expect(server.requests("POST", "/oauth/authorize_device").first?.form
                == ["client_id": "test-client", "scope": "api read_user write_repository"])
    }

    @Test("GitLab before 17.2 (no device endpoint) says to use a token")
    func oldGitLab() async {
        server.on("POST", "/oauth/authorize_device", status: 404, body: Data("<html>".utf8))
        await #expect(throws: HostingAuthError.deviceFlowUnsupported) {
            try await client.requestDeviceCode(clientId: "test-client")
        }
    }

    @Test("Poll answers come back as 400 with the OAuth error")
    func pollErrors() async throws {
        server.on("POST", "/oauth/token", status: 400, fixture: "oauth-pending")
        #expect(try await client.pollTokenOnce(clientId: "test-client", deviceCode: "d") == .pending)
        server.on("POST", "/oauth/token", status: 400, fixture: "oauth-expired-token")
        _ = try await client.pollTokenOnce(clientId: "test-client", deviceCode: "d")   // the queued pending
        await #expect(throws: HostingAuthError.expiredToken) {
            try await client.pollTokenOnce(clientId: "test-client", deviceCode: "d")
        }
        #expect(server.requests("POST", "/oauth/token").first?.form
                == ["grant_type": "urn:ietf:params:oauth:grant-type:device_code", "device_code": "d", "client_id": "test-client"])
    }

    @Test("Access denied ends the poll")
    func denied() async {
        server.on("POST", "/oauth/token", status: 400, fixture: "oauth-access-denied")
        await #expect(throws: HostingAuthError.accessDenied) {
            try await client.pollTokenOnce(clientId: "test-client", deviceCode: "d")
        }
    }

    @Test("A granted token carries its refresh token and lifetime")
    func granted() async throws {
        server.on("POST", "/oauth/token", fixture: "gitlab-token-granted")
        let outcome = try await client.pollTokenOnce(clientId: "test-client", deviceCode: "d")
        #expect(outcome == .granted(TokenGrant(accessToken: "test-gitlab-access", refreshToken: "test-gitlab-refresh-2",
                                               expiresIn: 7200, scopes: ["api", "read_user", "write_repository"])))
    }

    @Test("Refresh sends the refresh token and client id and returns the rotated pair")
    func refresh() async throws {
        server.on("POST", "/oauth/token", fixture: "gitlab-token-granted")
        let grant = try await client.refresh(clientId: "test-client", refreshToken: "test-gitlab-refresh-1")
        #expect(grant.refreshToken == "test-gitlab-refresh-2")
        #expect(server.requests("POST", "/oauth/token").first?.form
                == ["grant_type": "refresh_token", "refresh_token": "test-gitlab-refresh-1", "client_id": "test-client"])
    }

    @Test("A refused refresh token is refreshRejected")
    func refreshRejected() async {
        server.on("POST", "/oauth/token", status: 400, fixture: "oauth-invalid-grant")
        await #expect(throws: HostingAuthError.refreshRejected) {
            try await client.refresh(clientId: "test-client", refreshToken: "test-gitlab-refresh-1")
        }
    }

    @Test("A personal token: /user plus /personal_access_tokens/self for scopes and expiry")
    func validatesPersonalToken() async throws {
        server.on("GET", "/api/v4/user", fixture: "gitlab-user")
        server.on("GET", "/api/v4/personal_access_tokens/self", fixture: "gitlab-pat-self")
        let validation = try await client.validate(token: "test-token", method: .personalToken)
        #expect(validation.user == HostingUser(login: "tanuki-test", displayName: "Tanuki Test",
                                               avatarURL: URL(string: "https://gitlab.example.test/uploads/avatar.png")))
        #expect(validation.scopes == ["api"])
        #expect(validation.expiresAt == ISO8601DateFormatter().date(from: "2026-12-31T00:00:00Z"))
        #expect(server.requests("GET", "/api/v4/personal_access_tokens/self").first?.header("Authorization") == "Bearer test-token")
    }

    @Test("A revoked or inactive token is refused")
    func inactive() async {
        server.on("GET", "/api/v4/user", fixture: "gitlab-user")
        server.on("GET", "/api/v4/personal_access_tokens/self", fixture: "gitlab-pat-self-revoked")
        await #expect(throws: HostingAuthError.inactiveToken) {
            try await client.validate(token: "test-token", method: .personalToken)
        }
    }

    @Test("A read-only token is refused, naming what's missing")
    func readOnly() async {
        server.on("GET", "/api/v4/user", fixture: "gitlab-user")
        server.on("GET", "/api/v4/personal_access_tokens/self", fixture: "gitlab-pat-self-read-only")
        await #expect(throws: HostingAuthError.missingScopes(["api", "write_repository"])) {
            try await client.validate(token: "test-token", method: .personalToken)
        }
    }

    @Test("GitLab without /self (before 15.5): scopes not verifiable")
    func noSelfEndpoint() async throws {
        server.on("GET", "/api/v4/user", fixture: "gitlab-user")
        server.on("GET", "/api/v4/personal_access_tokens/self", status: 404, body: Data(#"{"error":"404 Not Found"}"#.utf8))
        let validation = try await client.validate(token: "test-token", method: .personalToken)
        #expect(validation.scopes == nil)
        #expect(validation.user.login == "tanuki-test")
    }

    @Test("An OAuth token is checked with /user only")
    func oauthToken() async throws {
        server.on("GET", "/api/v4/user", fixture: "gitlab-user")
        let validation = try await client.validate(token: "test-token", method: .oauth)
        #expect(validation.scopes == nil)
        #expect(server.requests("GET", "/api/v4/personal_access_tokens/self").isEmpty)
    }

    @Test("A rejected token is unauthorized")
    func unauthorized() async {
        server.on("GET", "/api/v4/user", status: 401, body: Data(#"{"message":"401 Unauthorized"}"#.utf8))
        await #expect(throws: HostingAuthError.unauthorized) {
            try await client.validate(token: "test-token", method: .personalToken)
        }
    }

    @Test("The factory picks the client for the instance kind")
    func factory() {
        #expect(HostingAuthClients.make(for: .gitHubDotCom) is GitHubAuthClient)
        #expect(HostingAuthClients.make(for: .gitLabDotCom) is GitLabAuthClient)
    }
}
