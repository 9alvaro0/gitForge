import Foundation
import Security
@testable import gitForge

/// Test double for `AccountSecretStore`.
final class InMemoryAccountSecretStore: AccountSecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var secrets: [UUID: AccountSecret] = [:]
    var failWrites = false

    func read(_ id: UUID) -> AccountSecret? {
        lock.withLock { secrets[id] }
    }

    func write(_ secret: AccountSecret, for id: UUID) throws {
        if failWrites { throw AccountSecretStoreError.keychain(errSecIO) }
        lock.withLock { secrets[id] = secret }
    }

    func delete(_ id: UUID) {
        _ = lock.withLock { secrets.removeValue(forKey: id) }
    }

    func forget(_ id: UUID) {}
}
