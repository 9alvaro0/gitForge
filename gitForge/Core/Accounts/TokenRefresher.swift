import Foundation

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
        guard let secret = secrets.read(account.id) else { throw HostingAuthError.missingSecret }
        guard Self.needsRefresh(secret, now: now()) else { return secret.accessToken }
        return try await refresh(account.id, on: instance, replacing: secret.accessToken).accessToken
    }

    /// Runs `operation` with the account's token. On a 401, an account that
    /// can refresh does so once and retries; a second 401 is the caller's.
    func perform<T: Sendable>(for account: HostingAccount, on instance: HostingInstance,
                              _ operation: @Sendable (String) async throws -> T) async throws -> T {
        let token = try await accessToken(for: account, on: instance)
        do {
            return try await operation(token)
        } catch HostingAuthError.unauthorized {
            guard secrets.read(account.id)?.refreshToken != nil else { throw HostingAuthError.unauthorized }
            let fresh = try await refresh(account.id, on: instance, replacing: token)
            return try await operation(fresh.accessToken)
        }
    }

    /// One refresh per account at a time. A caller whose token was already
    /// replaced by another caller's refresh gets the current secret.
    private func refresh(_ id: UUID, on instance: HostingInstance, replacing stale: String) async throws -> AccountSecret {
        if let running = inFlight[id] { return try await running.value }
        guard let current = secrets.read(id) else { throw HostingAuthError.missingSecret }
        if current.accessToken != stale, !Self.needsRefresh(current, now: now()) { return current }
        guard let refreshToken = current.refreshToken else { throw HostingAuthError.refreshRejected }
        guard let clientId = instance.oauthClientId, !clientId.isEmpty else { throw HostingAuthError.oauthUnavailable }

        let client = makeClient(instance)
        let secrets = self.secrets
        let now = self.now
        let onRejected = self.onRefreshRejected
        let task = Task<AccountSecret, Error> {
            do {
                let grant = try await client.refresh(clientId: clientId, refreshToken: refreshToken)
                var fresh = grant.secret(now: now())
                if fresh.refreshToken == nil { fresh.refreshToken = refreshToken }
                try secrets.write(fresh, for: id)
                return fresh
            } catch HostingAuthError.refreshRejected {
                await onRejected(id)
                throw HostingAuthError.refreshRejected
            }
        }
        inFlight[id] = task
        defer { inFlight[id] = nil }
        return try await task.value
    }
}
