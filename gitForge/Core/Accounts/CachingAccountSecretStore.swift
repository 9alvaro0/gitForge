import Foundation

/// Keeps each account's secret in memory once read, in front of the
/// Keychain. Every fetch, API call and Reviews refresh asks for a token, and
/// on the legacy keychain each read the app isn't trusted for is a password
/// prompt: reading the Keychain every time turned one missing "Always Allow"
/// into a prompt every few minutes. Now an account is read at most once per
/// launch (or again after `forget`).
///
/// Calls for one account run one at a time, so the concurrent first reads of
/// a launch make one Keychain read — one prompt — and the others get its
/// result; other accounts don't wait. Writes and deletes go through to the
/// Keychain and update the copy only when it accepted them. Only secrets are
/// kept: a missing or refused read is asked again next time.
nonisolated final class CachingAccountSecretStore: AccountSecretStore, @unchecked Sendable {
    private let base: any AccountSecretStore
    private let lock = NSLock()
    private var secrets: [UUID: AccountSecret] = [:]
    /// One per account: serialises its Keychain calls without holding `lock`
    /// while a read waits on a prompt.
    private var gates: [UUID: NSLock] = [:]

    init(_ base: any AccountSecretStore) {
        self.base = base
    }

    func read(_ id: UUID) -> AccountSecret? {
        if let kept = kept(id) { return kept }
        return oneAtATime(id) {
            // Filled by another caller while this one waited.
            if let kept = kept(id) { return kept }
            let secret = base.read(id)
            if let secret { keep(secret, for: id) }
            return secret
        }
    }

    func write(_ secret: AccountSecret, for id: UUID) throws {
        try oneAtATime(id) {
            try base.write(secret, for: id)
            keep(secret, for: id)
        }
    }

    func delete(_ id: UUID) {
        oneAtATime(id) {
            base.delete(id)
            keep(nil, for: id)
        }
    }

    func forget(_ id: UUID) {
        oneAtATime(id) {
            base.forget(id)
            keep(nil, for: id)
        }
    }

    private func kept(_ id: UUID) -> AccountSecret? {
        lock.withLock { secrets[id] }
    }

    private func keep(_ secret: AccountSecret?, for id: UUID) {
        lock.withLock { secrets[id] = secret }
    }

    private func oneAtATime<T>(_ id: UUID, _ body: () throws -> T) rethrows -> T {
        let gate = lock.withLock {
            if let gate = gates[id] { return gate }
            let gate = NSLock()
            gates[id] = gate
            return gate
        }
        gate.lock()
        defer { gate.unlock() }
        return try body()
    }
}
