import Foundation
import Security

/// The pre-accounts token store (one token per host, service
/// `com.warwarelabs.gitForge.remote-token`), kept only so phase 5b can copy
/// what's left and delete it (spec §4.4). Legacy macOS keychain, like
/// `KeychainAccountSecretStore`. Reads throw when the Keychain can't be
/// read, so that isn't taken for "no token".
nonisolated struct LegacyTokenKeychain: LegacyTokenStore {
    struct KeychainError: Error { let status: OSStatus }

    private let service = "com.warwarelabs.gitForge.remote-token"

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
    }

    func legacyHosts() throws -> [String] {
        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let items = result as? [[String: Any]] else { throw KeychainError(status: status) }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
    }

    func legacyToken(for host: String) throws -> String? {
        var query = baseQuery()
        query[kSecAttrAccount as String] = host
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
        return String(data: data, encoding: .utf8)
    }

    func removeLegacyToken(for host: String) throws {
        var query = baseQuery()
        query[kSecAttrAccount as String] = host
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}
