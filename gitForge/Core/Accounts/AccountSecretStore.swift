import Foundation
import Security
import os

/// Where account secrets live. The app uses the Keychain; tests use an
/// in-memory store. Nonisolated: the token refresher reads and writes
/// secrets off the main actor.
nonisolated protocol AccountSecretStore: Sendable {
    func read(_ id: UUID) -> AccountSecret?
    func write(_ secret: AccountSecret, for id: UUID) throws
    func delete(_ id: UUID)
}

nonisolated enum AccountSecretStoreError: LocalizedError, Equatable {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
            return "Couldn't save the account to the Keychain: \(detail)."
        }
    }
}

/// Legacy macOS keychain, like `RemoteCredentialsStore` (see its notes on why
/// no data-protection keychain or access group). One generic-password item
/// per account: account = lowercased UUID, data = JSON `AccountSecret`.
nonisolated struct KeychainAccountSecretStore: AccountSecretStore {
    private static let logger = Logger(subsystem: "com.warwarelabs.gitForge", category: "accounts")
    let service: String

    init(service: String = "com.warwarelabs.gitForge.account") {
        self.service = service
    }

    private func query(_ id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString.lowercased(),
        ]
    }

    func read(_ id: UUID) -> AccountSecret? {
        var query = query(id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                Self.logger.error("Keychain read failed (\(status, privacy: .public))")
            }
            return nil
        }
        do {
            return try JSONDecoder().decode(AccountSecret.self, from: data)
        } catch {
            Self.logger.error("Keychain item for account \(id.uuidString, privacy: .public) isn't a readable secret: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func write(_ secret: AccountSecret, for id: UUID) throws {
        let data = try JSONEncoder().encode(secret)
        let update = SecItemUpdate(query(id) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw AccountSecretStoreError.keychain(update) }
        var attributes = query(id)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let add = SecItemAdd(attributes as CFDictionary, nil)
        guard add == errSecSuccess else { throw AccountSecretStoreError.keychain(add) }
    }

    func delete(_ id: UUID) {
        _ = SecItemDelete(query(id) as CFDictionary)
    }
}
