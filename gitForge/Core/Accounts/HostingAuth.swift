import Foundation

/// What went wrong connecting or checking an account. Every
/// `HostingAuthClient` call, `TokenRefresher` and `AccountConnector` throw
/// only this, so the UI has one type to explain.
nonisolated enum HostingAuthError: LocalizedError, Equatable, Sendable {
    case network(String)
    case tls(String)
    /// 401: the token is unknown, revoked or expired.
    case unauthorized
    case forbidden
    case server(Int)
    case decoding(String)
    /// An OAuth error code the flow doesn't handle on its own.
    case oauth(String)
    /// The instance has no OAuth client id: token sign-in only.
    case oauthUnavailable
    /// No device flow here (GitLab before 17.2, or disabled on the OAuth app).
    case deviceFlowUnsupported
    /// The device code expired before the user approved it.
    case expiredToken
    /// The user declined in the browser.
    case accessDenied
    /// The server refused the refresh token: the account must reconnect.
    case refreshRejected
    case missingScopes([String])
    /// GitLab reports the token as revoked or inactive.
    case inactiveToken
    /// The account's secret couldn't be read from the Keychain.
    case missingSecret
    /// The Keychain or `accounts.json` refused to save the account.
    case storage(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .network(let message): String(localized: "Couldn't reach the server: \(message)")
        case .tls(let message): String(localized: "The server's certificate isn't trusted: \(message)")
        case .unauthorized: String(localized: "The token was rejected. It may have been revoked or have expired.")
        case .forbidden: String(localized: "The token isn't allowed to read your user. Check its scopes.")
        case .server(let status): String(localized: "The server answered with an error (\(status)).")
        case .decoding: String(localized: "The server's answer couldn't be read.")
        case .oauth(let code): String(localized: "The server refused the sign-in (\(code)).")
        case .oauthUnavailable: String(localized: "Signing in with the browser isn't set up for this instance. Use a token instead.")
        case .deviceFlowUnsupported: String(localized: "This server doesn't support signing in with a code (GitLab needs 17.2 or later). Use a token instead.")
        case .expiredToken: String(localized: "The code expired before it was approved. Start again.")
        case .accessDenied: String(localized: "The sign-in was declined in the browser.")
        case .refreshRejected: String(localized: "The session expired. Reconnect the account.")
        case .missingScopes(let scopes): String(localized: "The token is missing these scopes: \(scopes.joined(separator: ", ")).")
        case .inactiveToken: String(localized: "The token has been revoked or is no longer active.")
        case .missingSecret: String(localized: "The account's token couldn't be read from the Keychain.")
        case .storage(let message): String(localized: "Couldn't save the account: \(message)")
        case .cancelled: String(localized: "Cancelled.")
        }
    }

    /// Any error from connecting, as a `HostingAuthError`. Keychain and store
    /// errors become `.storage`.
    static func wrapping(_ error: any Error) -> HostingAuthError {
        switch error {
        case let error as HostingAuthError: error
        case is CancellationError: .cancelled
        default: .storage(error.localizedDescription)
        }
    }
}

/// What the device-code endpoint returns: the code the user types in the
/// browser and how long and how often to wait for it.
nonisolated struct DeviceCode: Equatable, Sendable {
    var deviceCode: String
    var userCode: String
    var verificationURI: URL
    /// GitLab: the same page with the code already filled in.
    var verificationURIComplete: URL?
    /// Seconds until the code stops working.
    var expiresIn: Int
    /// Seconds between polls.
    var interval: Int
}

nonisolated enum DevicePollOutcome: Equatable, Sendable {
    case pending
    /// `interval`: the new interval, when the server sends one.
    case slowDown(interval: Int?)
    case granted(TokenGrant)
}

/// A token from the token endpoint (device flow or refresh).
nonisolated struct TokenGrant: Equatable, Sendable {
    var accessToken: String
    var refreshToken: String?
    /// Seconds the access token lasts; `nil` = doesn't expire.
    var expiresIn: Int?
    /// What the server says it granted; `nil` when it doesn't say.
    var scopes: [String]?

    func secret(now: Date) -> AccountSecret {
        AccountSecret(accessToken: accessToken, refreshToken: refreshToken,
                      accessTokenExpiresAt: expiresIn.map { now.addingTimeInterval(TimeInterval($0)) })
    }
}

/// Who a token belongs to, from `/user`.
nonisolated struct HostingUser: Equatable, Sendable {
    var login: String
    var displayName: String?
    var avatarURL: URL?
}

/// A token that works and has the required scopes.
nonisolated struct TokenValidation: Equatable, Sendable {
    var user: HostingUser
    /// `nil`: the server doesn't report them (GitHub fine-grained token,
    /// GitLab OAuth token or GitLab before 15.5) — "scopes not verifiable".
    var scopes: [String]?
    /// When the token itself stops working (personal token expiry).
    var expiresAt: Date?

    /// Required scopes the reported ones don't cover; empty when the server
    /// doesn't report scopes.
    func missingScopes(kind: HostingInstance.Kind) -> [String] {
        scopes.map { HostingScopes.missing($0, kind: kind) } ?? []
    }
}

/// Scopes gitForge needs (spec §5.1) and how to check a granted list.
nonisolated enum HostingScopes {
    static func required(for kind: HostingInstance.Kind) -> [String] {
        switch kind {
        case .github: ["repo", "read:org", "workflow"]
        case .gitlab: ["api", "read_user", "write_repository"]
        }
    }

    /// For the device-code request and the "create token" pages.
    static func requestString(for kind: HostingInstance.Kind) -> String {
        required(for: kind).joined(separator: " ")
    }

    /// Broader scopes that also grant a required one.
    private static let coveredBy: [String: [String]] = [
        "read:org": ["write:org", "admin:org"],
        "read_user": ["api"],
        "write_repository": ["api"],
    ]

    /// Required scopes `granted` doesn't cover, in the required order.
    static func missing(_ granted: [String], kind: HostingInstance.Kind) -> [String] {
        let have = Set(granted.map { $0.lowercased() })
        return required(for: kind).filter { scope in
            !have.contains(scope) && !(coveredBy[scope] ?? []).contains(where: have.contains)
        }
    }

    /// "Create token in browser" (spec §5.2): the instance's token page with
    /// the name and the required scopes already filled in.
    static func createTokenURL(for instance: HostingInstance) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = instance.host
        let scopes = required(for: instance.kind).joined(separator: ",")
        switch instance.kind {
        case .github:
            components.path = "/settings/tokens/new"
            components.queryItems = [URLQueryItem(name: "scopes", value: scopes),
                                     URLQueryItem(name: "description", value: "gitForge")]
        case .gitlab:
            components.path = "/-/user_settings/personal_access_tokens"
            components.queryItems = [URLQueryItem(name: "name", value: "gitForge"),
                                     URLQueryItem(name: "scopes", value: scopes)]
        }
        return components.url ?? instance.webBaseURL
    }

    /// `"repo, read:org"` (GitHub) or `"api read_user"` (GitLab).
    static func parse(_ raw: String) -> [String] {
        raw.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
    }
}

/// Bodies of the OAuth device-code and token endpoints. GitHub answers
/// errors with 200 and an `error` field; GitLab with 400 and the same field.
nonisolated enum OAuthResponse {
    static let deviceCodeGrant = "urn:ietf:params:oauth:grant-type:device_code"

    static func errorCode(_ data: Data) -> String? {
        (try? JSONDecoder().decode(OAuthErrorBody.self, from: data))?.error
    }

    static func deviceCode(_ data: Data, status: Int) throws -> DeviceCode {
        if status == 404 { throw HostingAuthError.deviceFlowUnsupported }
        if let error = errorCode(data) {
            throw error == "device_flow_disabled" ? HostingAuthError.deviceFlowUnsupported : HostingAuthError.oauth(error)
        }
        try HostingHTTP.check(status)
        let body = try HostingHTTP.decode(DeviceCodeBody.self, data)
        guard let uri = URL(string: body.verification_uri) else { throw HostingAuthError.decoding("verification_uri") }
        return DeviceCode(deviceCode: body.device_code, userCode: body.user_code, verificationURI: uri,
                          verificationURIComplete: body.verification_uri_complete.flatMap(URL.init(string:)),
                          expiresIn: body.expires_in, interval: body.interval ?? 5)
    }

    /// One device-flow poll.
    static func pollOutcome(_ data: Data, status: Int) throws -> DevicePollOutcome {
        if let body = try? JSONDecoder().decode(OAuthErrorBody.self, from: data) {
            switch body.error {
            case "authorization_pending": return .pending
            case "slow_down": return .slowDown(interval: body.interval)
            case "expired_token": throw HostingAuthError.expiredToken
            case "access_denied": throw HostingAuthError.accessDenied
            case "device_flow_disabled": throw HostingAuthError.deviceFlowUnsupported
            default: throw HostingAuthError.oauth(body.error)
            }
        }
        try HostingHTTP.check(status)
        return .granted(try grant(data))
    }

    /// A token refresh: any OAuth error, 400 or 401 means the refresh token
    /// is no good; a 5xx (even with an `error` body from a gateway) is worth
    /// retrying later.
    static func refreshOutcome(_ data: Data, status: Int) throws -> TokenGrant {
        if status >= 500 { throw HostingAuthError.server(status) }
        if errorCode(data) != nil || status == 400 || status == 401 { throw HostingAuthError.refreshRejected }
        try HostingHTTP.check(status)
        return try grant(data)
    }

    static func grant(_ data: Data) throws -> TokenGrant {
        let body = try HostingHTTP.decode(OAuthGrantBody.self, data)
        return TokenGrant(accessToken: body.access_token, refreshToken: body.refresh_token,
                          expiresIn: body.expires_in, scopes: body.scope.map(HostingScopes.parse))
    }
}

nonisolated private struct OAuthErrorBody: Decodable {
    let error: String
    let interval: Int?
}

nonisolated private struct OAuthGrantBody: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int?
    let scope: String?
}

nonisolated private struct DeviceCodeBody: Decodable {
    let device_code: String
    let user_code: String
    let verification_uri: String
    let verification_uri_complete: String?
    let expires_in: Int
    let interval: Int?
}

/// Sign-in and token checks for one instance (spec §5). Every call throws
/// `HostingAuthError`.
nonisolated protocol HostingAuthClient: Sendable {
    var instance: HostingInstance { get }
    func requestDeviceCode(clientId: String) async throws -> DeviceCode
    /// One request to the token endpoint. `pollToken` loops over it.
    func pollTokenOnce(clientId: String, deviceCode: String) async throws -> DevicePollOutcome
    /// A new access token from a refresh token (GitLab OAuth).
    func refresh(clientId: String, refreshToken: String) async throws -> TokenGrant
    func fetchUser(token: String) async throws -> HostingUser
    /// Checks a token: who it belongs to, the scopes it reports and its
    /// expiry. Missing scopes don't throw: callers decide with
    /// `TokenValidation.missingScopes(kind:)`, so a token short of scopes
    /// still records whose it is.
    func validate(token: String, method: HostingAccount.Method) async throws -> TokenValidation
}
