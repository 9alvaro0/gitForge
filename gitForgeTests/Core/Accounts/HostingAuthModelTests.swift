import Foundation
import Testing
@testable import gitForge

@Suite("Hosting auth — scopes, OAuth bodies and HTTP helpers")
struct HostingAuthModelTests {

    private func json(_ text: String) -> Data { Data(text.utf8) }

    @Test("Scope lists parse from commas or spaces")
    func parse() {
        #expect(HostingScopes.parse("repo, read:org,workflow") == ["repo", "read:org", "workflow"])
        #expect(HostingScopes.parse("api read_user  write_repository") == ["api", "read_user", "write_repository"])
        #expect(HostingScopes.parse("") == [])
    }

    @Test("Requested scopes per provider")
    func requested() {
        #expect(HostingScopes.requestString(for: .github) == "repo read:org workflow")
        #expect(HostingScopes.requestString(for: .gitlab) == "api read_user write_repository")
    }

    static let missingCases: [(HostingInstance.Kind, [String], [String])] = [
        (.github, ["repo", "read:org", "workflow"], []),
        (.github, ["repo", "admin:org", "workflow", "gist"], []),
        (.github, ["repo", "read:org"], ["workflow"]),
        (.github, [], ["repo", "read:org", "workflow"]),
        (.gitlab, ["api"], []),
        (.gitlab, ["read_user", "write_repository"], ["api"]),
        (.gitlab, ["read_api", "read_user"], ["api", "write_repository"]),
    ]

    @Test("Missing scopes, with broader scopes counting", arguments: missingCases)
    func missing(kind: HostingInstance.Kind, granted: [String], expected: [String]) {
        #expect(HostingScopes.missing(granted, kind: kind) == expected)
    }

    @Test("The create-token page comes with name and scopes filled in")
    func createTokenURL() {
        #expect(HostingScopes.createTokenURL(for: .gitHubDotCom).absoluteString
                == "https://github.com/settings/tokens/new?scopes=repo,read:org,workflow&description=gitForge")
        #expect(HostingScopes.createTokenURL(for: HostingInstance(kind: .gitlab, host: "git.empresa.com")).absoluteString
                == "https://git.empresa.com/-/user_settings/personal_access_tokens?name=gitForge&scopes=api,read_user,write_repository")
    }

    @Test("Poll bodies: pending, slow down and terminal errors")
    func pollBodies() throws {
        #expect(try OAuthResponse.pollOutcome(json(#"{"error":"authorization_pending"}"#), status: 200) == .pending)
        #expect(try OAuthResponse.pollOutcome(json(#"{"error":"slow_down","interval":10}"#), status: 400) == .slowDown(interval: 10))
        #expect(throws: HostingAuthError.expiredToken) {
            try OAuthResponse.pollOutcome(self.json(#"{"error":"expired_token"}"#), status: 400)
        }
        #expect(throws: HostingAuthError.accessDenied) {
            try OAuthResponse.pollOutcome(self.json(#"{"error":"access_denied"}"#), status: 400)
        }
        #expect(throws: HostingAuthError.deviceFlowUnsupported) {
            try OAuthResponse.pollOutcome(self.json(#"{"error":"device_flow_disabled"}"#), status: 200)
        }
        #expect(throws: HostingAuthError.oauth("incorrect_client_credentials")) {
            try OAuthResponse.pollOutcome(self.json(#"{"error":"incorrect_client_credentials"}"#), status: 200)
        }
    }

    @Test("A granted token: access, refresh, expiry and scopes")
    func granted() throws {
        let body = json(#"{"access_token":"a1","refresh_token":"r1","expires_in":7200,"scope":"api read_user"}"#)
        #expect(try OAuthResponse.pollOutcome(body, status: 200)
                == .granted(TokenGrant(accessToken: "a1", refreshToken: "r1", expiresIn: 7200, scopes: ["api", "read_user"])))
    }

    @Test("A grant becomes a secret whose expiry counts from now")
    func grantSecret() {
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(TokenGrant(accessToken: "a1", refreshToken: "r1", expiresIn: 7200, scopes: nil).secret(now: now)
                == AccountSecret(accessToken: "a1", refreshToken: "r1", accessTokenExpiresAt: Date(timeIntervalSince1970: 8_200)))
        #expect(TokenGrant(accessToken: "a1", refreshToken: nil, expiresIn: nil, scopes: nil).secret(now: now)
                == AccountSecret(accessToken: "a1"))
    }

    @Test("Any refresh error means the refresh token is no good; a 5xx doesn't")
    func refreshBodies() throws {
        #expect(throws: HostingAuthError.refreshRejected) {
            try OAuthResponse.refreshOutcome(self.json(#"{"error":"invalid_grant"}"#), status: 400)
        }
        #expect(throws: HostingAuthError.refreshRejected) {
            try OAuthResponse.refreshOutcome(Data(), status: 401)
        }
        #expect(throws: HostingAuthError.server(502)) {
            try OAuthResponse.refreshOutcome(Data(), status: 502)
        }
        #expect(throws: HostingAuthError.server(502)) {
            try OAuthResponse.refreshOutcome(self.json(#"{"error":"Bad Gateway"}"#), status: 502)
        }
        #expect(try OAuthResponse.refreshOutcome(json(#"{"access_token":"a2","refresh_token":"r2","expires_in":60}"#), status: 200).refreshToken == "r2")
    }

    @Test("Device code bodies; a missing interval defaults to 5 s; 404 means no device flow")
    func deviceCode() throws {
        let code = try OAuthResponse.deviceCode(json(#"{"device_code":"d","user_code":"ABCD-1234","verification_uri":"https://example.test/device","expires_in":900}"#), status: 200)
        #expect(code == DeviceCode(deviceCode: "d", userCode: "ABCD-1234", verificationURI: URL(string: "https://example.test/device")!,
                                   verificationURIComplete: nil, expiresIn: 900, interval: 5))
        #expect(throws: HostingAuthError.deviceFlowUnsupported) {
            try OAuthResponse.deviceCode(Data("<html>".utf8), status: 404)
        }
        #expect(throws: HostingAuthError.oauth("invalid_client")) {
            try OAuthResponse.deviceCode(self.json(#"{"error":"invalid_client"}"#), status: 401)
        }
    }

    @Test("HTTP status mapping")
    func statuses() throws {
        try HostingHTTP.check(204)
        #expect(throws: HostingAuthError.unauthorized) { try HostingHTTP.check(401) }
        #expect(throws: HostingAuthError.server(403)) { try HostingHTTP.check(403) }
        #expect(throws: HostingAuthError.server(404)) { try HostingHTTP.check(404) }
    }

    @Test("Form encoding escapes reserved characters")
    func formEncoding() {
        #expect(HostingHTTP.formEncode([("scope", "repo read:org"), ("grant_type", OAuthResponse.deviceCodeGrant)])
                == "scope=repo%20read%3Aorg&grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code")
    }

    @Test("Errors from elsewhere are wrapped")
    func wrapping() {
        #expect(HostingAuthError.wrapping(HostingAuthError.accessDenied) == .accessDenied)
        #expect(HostingAuthError.wrapping(CancellationError()) == .cancelled)
        #expect(HostingAuthError.wrapping(AccountStoreError.unknownInstance) == .storage("That instance no longer exists."))
    }

    @Test("The web base is the instance host over HTTPS")
    func webBase() {
        #expect(HostingInstance.gitHubDotCom.webBaseURL.absoluteString == "https://github.com")
        #expect(HostingInstance(kind: .gitlab, host: "Git.Empresa.com").webBaseURL.absoluteString == "https://git.empresa.com")
    }
}
