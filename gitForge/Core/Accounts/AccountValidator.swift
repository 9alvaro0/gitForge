import Foundation
import os

/// Checks each account against its API at launch, at most once a day per
/// account (spec §5.4), and records login, identity, scopes, expiry and
/// status. Copied tokens get their login here. Errors that say nothing about
/// the token (offline, TLS, server down) leave the account as it was, to be
/// retried on the next launch.
@MainActor
final class AccountValidator {
    nonisolated static let interval: TimeInterval = 24 * 60 * 60
    private static let logger = Logger(subsystem: "com.warwarelabs.gitForge", category: "accounts")

    private let store: AccountStore
    private let refresher: TokenRefresher
    private let makeClient: @Sendable (HostingInstance) -> any HostingAuthClient
    private let now: @Sendable () -> Date

    init(store: AccountStore, refresher: TokenRefresher,
         makeClient: @escaping @Sendable (HostingInstance) -> any HostingAuthClient = { HostingAuthClients.make(for: $0) },
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.refresher = refresher
        self.makeClient = makeClient
        self.now = now
    }

    /// Never checked, checked over 24 h ago, or the clock went backwards.
    nonisolated static func isDue(_ account: HostingAccount, now: Date) -> Bool {
        guard let last = account.lastValidatedAt else { return true }
        return last > now || now.timeIntervalSince(last) >= interval
    }

    /// Checks every due account, one after another.
    func validateDueAccounts() async {
        for account in store.accounts where Self.isDue(account, now: now()) {
            await validate(account)
        }
    }

    /// Checks one account now, whatever its last check ("Test connection").
    func validate(_ account: HostingAccount) async {
        guard let instance = store.instances.first(where: { $0.id == account.instanceId }) else { return }
        let client = makeClient(instance)
        let method = account.method
        do {
            let validation = try await refresher.perform(for: account, on: instance) { token in
                try await client.validate(token: token, method: method)
            }
            store.applyValidation(validation, to: account.id, now: now())
        } catch {
            let error = HostingAuthError.wrapping(error)
            if let reason = AccountStatusPolicy.reason(for: error) {
                Self.logger.notice("Account \(account.id.uuidString, privacy: .public) on \(instance.host, privacy: .public) needs attention: \(error.localizedDescription, privacy: .public)")
                store.markNeedsAttention(account.id, reason, validatedAt: now())
            } else {
                Self.logger.error("Couldn't check account \(account.id.uuidString, privacy: .public) on \(instance.host, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
