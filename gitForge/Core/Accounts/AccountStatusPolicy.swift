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
    static func reason(for error: HostingAuthError) -> HostingAccount.Reason? {
        switch error {
        case .unauthorized, .inactiveToken: .revoked
        case .refreshRejected: .expired
        case .missingScopes, .forbidden: .missingScopes
        default: nil
        }
    }
}
