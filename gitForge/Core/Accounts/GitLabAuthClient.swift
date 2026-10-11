import Foundation

/// Sign-in and token checks for gitlab.com and self-managed GitLab. Device
/// flow needs GitLab 17.2+; older servers answer 404 and get tokens only.
nonisolated struct GitLabAuthClient: HostingAuthClient {
    let instance: HostingInstance
    let http: HostingHTTP

    func requestDeviceCode(clientId: String) async throws -> DeviceCode {
        let (data, response) = try await http.postForm(instance.webBaseURL.appending(path: "oauth/authorize_device"), [
            ("client_id", clientId),
            ("scope", HostingScopes.requestString(for: .gitlab)),
        ])
        return try OAuthResponse.deviceCode(data, status: response.statusCode)
    }

    func pollTokenOnce(clientId: String, deviceCode: String) async throws -> DevicePollOutcome {
        let (data, response) = try await http.postForm(instance.webBaseURL.appending(path: "oauth/token"), [
            ("grant_type", OAuthResponse.deviceCodeGrant),
            ("device_code", deviceCode),
            ("client_id", clientId),
        ])
        return try OAuthResponse.pollOutcome(data, status: response.statusCode)
    }

    /// GitLab rotates the refresh token: the grant carries a new one.
    func refresh(clientId: String, refreshToken: String) async throws -> TokenGrant {
        let (data, response) = try await http.postForm(instance.webBaseURL.appending(path: "oauth/token"), [
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
            ("client_id", clientId),
        ])
        return try OAuthResponse.refreshOutcome(data, status: response.statusCode)
    }

    func fetchUser(token: String) async throws -> HostingUser {
        let (data, _) = try await http.get(instance.apiBaseURL.appending(path: "user"), token: token)
        let body = try HostingHTTP.decode(GitLabUserBody.self, data)
        return HostingUser(login: body.username, displayName: body.name,
                           avatarURL: body.avatar_url.flatMap(URL.init(string:)))
    }

    /// Personal tokens: `/user` plus `/personal_access_tokens/self` (scopes,
    /// `active`, `expires_at`). OAuth tokens: `/user` only; their scopes come
    /// from the grant. If `/self` isn't there (GitLab before 15.5) or isn't
    /// allowed, the scopes can't be checked and the token is accepted.
    func validate(token: String, method: HostingAccount.Method) async throws -> TokenValidation {
        let user = try await fetchUser(token: token)
        guard method == .personalToken else { return TokenValidation(user: user, scopes: nil, expiresAt: nil) }
        let data: Data
        do {
            data = try await http.get(instance.apiBaseURL.appending(path: "personal_access_tokens/self"), token: token).0
        } catch HostingAuthError.forbidden {
            return TokenValidation(user: user, scopes: nil, expiresAt: nil)
        } catch HostingAuthError.server(let status) where status == 403 || status == 404 {
            return TokenValidation(user: user, scopes: nil, expiresAt: nil)
        }
        let body = try HostingHTTP.decode(GitLabTokenBody.self, data)
        if body.revoked == true || body.active == false { throw HostingAuthError.inactiveToken }
        return TokenValidation(user: user, scopes: body.scopes, expiresAt: Self.parseDay(body.expires_at))
    }

    /// `2026-12-31`: the token stops working at the start of that day (UTC).
    static func parseDay(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: raw)
    }
}

nonisolated private struct GitLabUserBody: Decodable {
    let username: String
    let name: String?
    let avatar_url: String?
}

nonisolated private struct GitLabTokenBody: Decodable {
    let scopes: [String]
    let active: Bool?
    let revoked: Bool?
    let expires_at: String?
}

/// The auth client for an instance's kind.
nonisolated enum HostingAuthClients {
    static func make(for instance: HostingInstance, http: HostingHTTP = .live) -> any HostingAuthClient {
        switch instance.kind {
        case .github: GitHubAuthClient(instance: instance, http: http)
        case .gitlab: GitLabAuthClient(instance: instance, http: http)
        }
    }
}
