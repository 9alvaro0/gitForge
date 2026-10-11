import Foundation

/// Sign-in and token checks for github.com and GitHub Enterprise Server.
/// OAuth endpoints are on the web host; `/user` on the API base.
nonisolated struct GitHubAuthClient: HostingAuthClient {
    let instance: HostingInstance
    let http: HostingHTTP

    func requestDeviceCode(clientId: String) async throws -> DeviceCode {
        let (data, response) = try await http.postForm(instance.webBaseURL.appending(path: "login/device/code"), [
            ("client_id", clientId),
            ("scope", HostingScopes.requestString(for: .github)),
        ])
        return try OAuthResponse.deviceCode(data, status: response.statusCode)
    }

    func pollTokenOnce(clientId: String, deviceCode: String) async throws -> DevicePollOutcome {
        let (data, response) = try await http.postForm(instance.webBaseURL.appending(path: "login/oauth/access_token"), [
            ("client_id", clientId),
            ("device_code", deviceCode),
            ("grant_type", OAuthResponse.deviceCodeGrant),
        ])
        return try OAuthResponse.pollOutcome(data, status: response.statusCode)
    }

    /// OAuth App tokens don't expire, so there's nothing to refresh.
    func refresh(clientId: String, refreshToken: String) async throws -> TokenGrant {
        throw HostingAuthError.refreshRejected
    }

    func fetchUser(token: String) async throws -> HostingUser {
        try await user(token: token).user
    }

    /// `/user` plus `X-OAuth-Scopes`. Without that header (fine-grained
    /// token) the scopes can't be checked and the token is accepted.
    func validate(token: String, method: HostingAccount.Method) async throws -> TokenValidation {
        let (user, response) = try await user(token: token)
        let scopes = response.value(forHTTPHeaderField: "X-OAuth-Scopes").map(HostingScopes.parse)
        if let scopes {
            let missing = HostingScopes.missing(scopes, kind: .github)
            guard missing.isEmpty else { throw HostingAuthError.missingScopes(missing) }
        }
        let expiry = Self.parseExpiration(response.value(forHTTPHeaderField: "github-authentication-token-expiration"))
        return TokenValidation(user: user, scopes: scopes, expiresAt: expiry)
    }

    /// `2026-10-14 12:00:00 UTC` (or with a numeric offset).
    static func parseExpiration(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.date(from: raw.replacingOccurrences(of: " UTC", with: " +0000"))
    }

    private func user(token: String) async throws -> (user: HostingUser, response: HTTPURLResponse) {
        let (data, response) = try await http.get(instance.apiBaseURL.appending(path: "user"), token: token)
        let body = try HostingHTTP.decode(GitHubUserBody.self, data)
        return (HostingUser(login: body.login, displayName: body.name,
                            avatarURL: body.avatar_url.flatMap(URL.init(string:))), response)
    }
}

nonisolated private struct GitHubUserBody: Decodable {
    let login: String
    let name: String?
    let avatar_url: String?
}
