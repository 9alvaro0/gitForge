import Foundation

/// Writing sign-in and validation results back to the accounts.
extension AccountStore {
    /// Saves a connected account. The account updated in place — keeping its
    /// id, profile link and repo assignments — is `replacedId` ("Reconnect",
    /// which also covers copied accounts that never got a login) or else the
    /// instance's account with the same login (any case); the old-token sync
    /// stops feeding it. The secret is written first: if the Keychain
    /// refuses, nothing changes. Callers check the scopes before saving.
    @discardableResult
    func connectAccount(instanceId: UUID, method: HostingAccount.Method, validation: TokenValidation,
                        grantedScopes: [String]? = nil, secret: AccountSecret, now: Date,
                        replacing replacedId: UUID? = nil) throws -> HostingAccount {
        let login = validation.user.login
        let replaced = replacedId.flatMap { id in accounts.first { $0.id == id && $0.instanceId == instanceId } }
        let existing = replaced
            ?? accounts.first { $0.instanceId == instanceId && $0.login?.lowercased() == login.lowercased() }
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

    /// Records a completed check. Scopes the server didn't report: an OAuth
    /// account keeps the ones it was granted; a token account has none
    /// ("not verifiable"). Reported scopes short of the required ones leave
    /// the account `needsAttention(.missingScopes)`, with its identity and
    /// scopes kept so the UI can say what's missing.
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
        let kind = instances.first { $0.id == account.instanceId }?.kind
        if let kind, !validation.missingScopes(kind: kind).isEmpty {
            account.status = .needsAttention(.missingScopes)
        } else {
            account.status = AccountStatusPolicy.status(expiresAt: validation.expiresAt, now: now)
        }
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
