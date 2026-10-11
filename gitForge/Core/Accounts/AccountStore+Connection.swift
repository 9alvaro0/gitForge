import Foundation

/// Writing sign-in and validation results back to the accounts.
extension AccountStore {
    /// Saves a connected account. If the instance already has one with the
    /// same login (any case), that one is updated in place — its id, profile
    /// link and repo assignments stay — and the old-token sync stops feeding
    /// it. The secret is written first: if the Keychain refuses, nothing
    /// changes.
    @discardableResult
    func connectAccount(instanceId: UUID, method: HostingAccount.Method, validation: TokenValidation,
                        grantedScopes: [String]? = nil, secret: AccountSecret, now: Date) throws -> HostingAccount {
        let login = validation.user.login
        let existing = accounts.first { $0.instanceId == instanceId && $0.login?.lowercased() == login.lowercased() }
        var account = existing ?? HostingAccount(instanceId: instanceId, method: method)
        account.method = method
        account.login = login
        account.displayName = validation.user.displayName
        account.avatarURL = validation.user.avatarURL
        account.scopes = validation.scopes ?? grantedScopes ?? []
        account.expiresAt = validation.expiresAt
        account.lastValidatedAt = now
        account.status = AccountStatusPolicy.status(expiresAt: validation.expiresAt, now: now)
        if existing != nil {
            try secrets.write(secret, for: account.id)
            detachFromLegacy(account.id)
            updateAccount(account)
        } else {
            try addAccount(account, secret: secret)
        }
        return account
    }

    /// Records a successful check. Scopes the server didn't report: an OAuth
    /// account keeps the ones it was granted; a token account has none
    /// ("not verifiable").
    func applyValidation(_ validation: TokenValidation, to accountId: UUID, now: Date) {
        guard var account = accounts.first(where: { $0.id == accountId }) else { return }
        account.login = validation.user.login
        account.displayName = validation.user.displayName
        account.avatarURL = validation.user.avatarURL
        if let scopes = validation.scopes {
            account.scopes = scopes
        } else if account.method == .personalToken {
            account.scopes = []
        }
        account.expiresAt = validation.expiresAt
        account.lastValidatedAt = now
        account.status = AccountStatusPolicy.status(expiresAt: validation.expiresAt, now: now)
        updateAccount(account)
    }

    /// `validatedAt`: set when this comes from a completed check, so the
    /// 24 h wait applies; a failed refresh leaves the last check alone.
    func markNeedsAttention(_ accountId: UUID, _ reason: HostingAccount.Reason, validatedAt: Date? = nil) {
        guard var account = accounts.first(where: { $0.id == accountId }) else { return }
        account.status = .needsAttention(reason)
        if let validatedAt { account.lastValidatedAt = validatedAt }
        updateAccount(account)
    }
}
