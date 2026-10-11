import Foundation

/// One identity on a `HostingInstance`. The token lives in the Keychain
/// (`AccountSecretStore`), keyed by `id`; everything here is safe to write
/// to `accounts.json`.
nonisolated struct HostingAccount: Codable, Identifiable, Equatable, Sendable {
    enum Method: String, Codable, Sendable { case oauth, personalToken }

    enum Reason: String, Codable, Sendable { case expired, revoked, missingScopes, unreachable }

    enum Status: Codable, Equatable, Sendable {
        case ok
        /// Created without checking the API yet (migrated tokens).
        case unverified
        case expiringSoon
        case needsAttention(Reason)
    }

    var id: UUID
    var instanceId: UUID
    /// `nil` until validated (migrated tokens get it in phase 2).
    var login: String?
    var displayName: String?
    var avatarURL: URL?
    var method: Method
    var scopes: [String]
    var expiresAt: Date?
    var lastValidatedAt: Date?
    var status: Status
    var linkedProfileId: UUID?

    init(id: UUID = UUID(), instanceId: UUID, login: String? = nil, displayName: String? = nil,
         avatarURL: URL? = nil, method: Method, scopes: [String] = [], expiresAt: Date? = nil,
         lastValidatedAt: Date? = nil, status: Status = .unverified, linkedProfileId: UUID? = nil) {
        self.id = id
        self.instanceId = instanceId
        self.login = login
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.method = method
        self.scopes = scopes
        self.expiresAt = expiresAt
        self.lastValidatedAt = lastValidatedAt
        self.status = status
        self.linkedProfileId = linkedProfileId
    }
}

/// What the Keychain holds for an account.
nonisolated struct AccountSecret: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var accessTokenExpiresAt: Date?

    init(accessToken: String, refreshToken: String? = nil, accessTokenExpiresAt: Date? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
    }
}
