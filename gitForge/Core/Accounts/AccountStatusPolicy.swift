import Foundation

/// How a check's result maps to an account's status (spec §4.2, §5.4).
nonisolated enum AccountStatusPolicy {
    static let expiringSoonWindow: TimeInterval = 7 * 24 * 60 * 60

    /// `ok`, `expiringSoon` with under 7 days left, or expired.
    static func status(expiresAt: Date?, now: Date) -> HostingAccount.Status {
        guard let expiresAt else { return .ok }
        if expiresAt <= now { return .needsAttention(.expired) }
        return expiresAt.timeIntervalSince(now) < expiringSoonWindow ? .expiringSoon : .ok
    }

    /// The reason an error gives the account, or `nil` when it says nothing
    /// about the token (offline, TLS, server down, Keychain): the status
    /// stays and the check is retried later.
    /// Why a server rejected a token: expired when its known expiry has
    /// passed, revoked otherwise.
    static func rejectionReason(expiresAt: Date?, now: Date = Date()) -> HostingAccount.Reason {
        if let expiresAt, expiresAt <= now { .expired } else { .revoked }
    }

    /// A 401 for a token whose known expiry has passed means it expired,
    /// not that it was revoked.
    static func reason(for error: HostingAuthError, expiresAt: Date? = nil, now: Date = Date()) -> HostingAccount.Reason? {
        switch error {
        case .unauthorized: rejectionReason(expiresAt: expiresAt, now: now)
        case .inactiveToken: .revoked
        // `oauthUnavailable`: the token needs a refresh but the instance
        // lost its OAuth client id, so only reconnecting brings it back.
        case .refreshRejected, .oauthUnavailable: .expired
        case .missingScopes, .forbidden: .missingScopes
        default: nil
        }
    }
}
