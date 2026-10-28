import Foundation
import os

/// Keeps OAuth access tokens usable (spec §5.3): refreshes when under 5
/// minutes are left and, after a 401, once more before giving up.
///
/// Refreshes are serialised per account: a GitLab refresh token works once,
/// so two concurrent refreshes would leave the account with a dead token.
/// Callers that arrive while one is running wait for it.
actor TokenRefresher {
    static let margin: TimeInterval = 5 * 60

    private let secrets: AccountSecretStore
    private let makeClient: @Sendable (HostingInstance) -> any HostingAuthClient
    private let now: @Sendable () -> Date
    private let onRefreshRejected: @Sendable (UUID) async -> Void
    private var inFlight: [UUID: Task<AccountSecret, Error>] = [:]
    /// Refreshed secrets the Keychain refused to save, with the refresh
    /// token they replaced. GitLab's refresh token works once, so losing the
    /// new pair would leave the account expired; the write is retried on the
    /// next read.
    private var unsaved: [UUID: (secret: AccountSecret, replacedRefreshToken: String)] = [:]
    private static let logger = Logger(subsystem: "com.warwarelabs.gitForge", category: "accounts")

    /// `onRefreshRejected`: the server refused the refresh token; the app
    /// marks the account `needsAttention(.expired)`.
    init(secrets: AccountSecretStore,
         makeClient: @escaping @Sendable (HostingInstance) -> any HostingAuthClient = { HostingAuthClients.make(for: $0) },
         now: @escaping @Sendable () -> Date = { Date() },
         onRefreshRejected: @escaping @Sendable (UUID) async -> Void = { _ in }) {
        self.secrets = secrets
        self.makeClient = makeClient
        self.now = now
        self.onRefreshRejected = onRefreshRejected
    }

    /// Only secrets with a refresh token and a known expiry are refreshed.
    static func needsRefresh(_ secret: AccountSecret, now: Date) -> Bool {
        guard secret.refreshToken != nil, let expiry = secret.accessTokenExpiresAt else { return false }
        return expiry.timeIntervalSince(now) < margin
    }

    /// A usable access token for `account`, refreshed first if it's about
    /// to expire.
    func accessToken(for account: HostingAccount, on instance: HostingInstance) async throws -> String {
        guard let secret = read(account.id) else { throw HostingAuthError.missingSecret }
        guard Self.needsRefresh(secret, now: now()) else { return secret.accessToken }
        return try await refresh(account.id, on: instance, replacing: secret.accessToken).accessToken
    }

    /// Runs `operation` with the account's token. When it fails with a
    /// rejection (`isRejection`: a 401 from the API by default, git's own
    /// for git), an account that can refresh does so once and retries; the
    /// second failure, or the first one of an account that can't refresh,
    /// goes back to the caller unchanged.
    func perform<T: Sendable>(for account: HostingAccount, on instance: HostingInstance,
                              retryingWhen isRejection: @Sendable (any Error) -> Bool = { ($0 as? HostingAuthError) == .unauthorized },
                              _ operation: @Sendable (String) async throws -> T) async throws -> T {
        let token = try await accessToken(for: account, on: instance)
        do {
            return try await operation(token)
        } catch let error where isRejection(error) {
            guard read(account.id)?.refreshToken != nil else { throw error }
            let fresh = try await refresh(account.id, on: instance, replacing: token)
            return try await operation(fresh.accessToken)
        }
    }

    /// A fresh token after `rejected` got a 401 from an API the caller
    /// drives itself: one refresh (shared with any running one). Accounts
    /// that can't refresh throw `unauthorized`.
    func refreshAfterRejection(for account: HostingAccount, on instance: HostingInstance,
                               rejected: String) async throws -> String {
        guard read(account.id)?.refreshToken != nil else { throw HostingAuthError.unauthorized }
        return try await refresh(account.id, on: instance, replacing: rejected).accessToken
    }

    /// One refresh per account at a time. A caller whose token was already
    /// replaced by another caller's refresh gets the current secret.
    private func refresh(_ id: UUID, on instance: HostingInstance, replacing stale: String) async throws -> AccountSecret {
        if let running = inFlight[id] { return try await running.value }
        // From the Keychain, not the in-memory copy: another copy of the app
        // (a Debug build next to the installed one) may have refreshed
        // already and spent the single-use refresh token this one remembers.
        secrets.forget(id)
        guard let current = read(id) else { throw HostingAuthError.missingSecret }
        if current.accessToken != stale, !Self.needsRefresh(current, now: now()) { return current }
        guard let refreshToken = current.refreshToken else { throw HostingAuthError.refreshRejected }
        guard let clientId = instance.oauthClientId, !clientId.isEmpty else { throw HostingAuthError.oauthUnavailable }

        let client = makeClient(instance)
        let now = self.now
        let task = Task<AccountSecret, Error> {
            let grant = try await client.refresh(clientId: clientId, refreshToken: refreshToken)
            var fresh = grant.secret(now: now())
            if fresh.refreshToken == nil { fresh.refreshToken = refreshToken }
            return fresh
        }
        inFlight[id] = task
        defer { inFlight[id] = nil }
        do {
            let fresh = try await task.value
            // Reconnected while the refresh ran: the new connection wins.
            if let reconnected = reconnection(of: id, since: refreshToken) { return reconnected }
            save(fresh, for: id, replacing: refreshToken)
            return fresh
        } catch HostingAuthError.refreshRejected {
            if let reconnected = reconnection(of: id, since: refreshToken) { return reconnected }
            await onRefreshRejected(id)
            throw HostingAuthError.refreshRejected
        }
    }

    /// The account's secret: one the Keychain refused (saved now if it can
    /// be), unless the account was reconnected since.
    private func read(_ id: UUID) -> AccountSecret? {
        let stored = secrets.read(id)
        guard let pending = unsaved[id] else { return stored }
        guard stored == nil || stored?.refreshToken == pending.replacedRefreshToken else {
            unsaved[id] = nil
            return stored
        }
        if (try? secrets.write(pending.secret, for: id)) != nil { unsaved[id] = nil }
        return pending.secret
    }

    /// The secret saved for `id` after a reconnect, if it no longer carries
    /// `refreshToken` (the one a running refresh used).
    private func reconnection(of id: UUID, since refreshToken: String) -> AccountSecret? {
        guard let stored = secrets.read(id), stored.refreshToken != refreshToken else { return nil }
        unsaved[id] = nil
        return stored
    }

    private func save(_ fresh: AccountSecret, for id: UUID, replacing refreshToken: String) {
        do {
            try secrets.write(fresh, for: id)
            unsaved[id] = nil
        } catch {
            Self.logger.error("Couldn't save the refreshed token for \(id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public); keeping it in memory")
            unsaved[id] = (fresh, refreshToken)
        }
    }
}
