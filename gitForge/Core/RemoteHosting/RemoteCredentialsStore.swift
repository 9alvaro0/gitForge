import Foundation
import Security
import os

/// Stores Personal Access Tokens for remote hosts (GitHub / GitLab) in the
/// macOS Keychain. Keyed by host (e.g. `github.com`, `gitlab.com`,
/// `gitlab.example.org` for self-hosted).
///
/// Holds no mutable state — Keychain APIs are themselves thread-safe — so it
/// ships as a `Sendable` value type with namespace-style methods.
///
/// Uses the legacy macOS keychain (no `kSecUseDataProtectionKeychain`, no
/// access group), the same strategy Tower / Fork / Sourcetree follow. The
/// keychain ACL keys items by the writing app's *designated requirement*,
/// which stays constant across releases as long as we keep signing with the
/// same Developer ID Application certificate (Team ID + bundle ID). Result:
/// the user sees a single "Always Allow" prompt on first save and that
/// permission persists across every subsequent app update. We do **not** use
/// `keychain-access-groups`: that entitlement is only needed when sharing
/// items with sibling apps / extensions, and it requires a Developer ID
/// provisioning profile we don't ship.
struct RemoteCredentialsStore: Sendable {
    static let shared = RemoteCredentialsStore()
    static let logger = Logger(subsystem: "com.warwarelabs.gitForge", category: "credentials")

    private let service = "com.warwarelabs.gitForge.remote-token"

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
    }

    /// Returns the token stored for `host`, or nil if none exists / Keychain
    /// access fails.
    func token(for host: String) -> String? {
        var query = baseQuery()
        query[kSecAttrAccount as String] = host
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            if status != errSecItemNotFound {
                Self.logger.error("Keychain read for \(host, privacy: .public) failed (\(status, privacy: .public))")
            } else {
                Self.logger.debug("Keychain miss for \(host, privacy: .public)")
            }
            return nil
        }
        Self.logger.debug("Keychain hit for \(host, privacy: .public) (\(token.count) chars)")
        return token
    }

    /// Set/replace the token for `host`. Empty / whitespace-only tokens delete
    /// any existing entry. Returns `nil` on success or a human-readable error
    /// message on failure (so the UI can surface Keychain access issues).
    @discardableResult
    func setToken(_ token: String?, for host: String) -> String? {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            removeToken(for: host)
            return nil
        }

        let data = Data(trimmed.utf8)

        // Try update first; fall back to add when nothing existed.
        var updateQuery = baseQuery()
        updateQuery[kSecAttrAccount as String] = host
        let updateAttrs: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecSuccess { return nil }

        if updateStatus != errSecItemNotFound {
            Self.logger.error("Keychain SecItemUpdate failed (\(updateStatus, privacy: .public)) for host \(host, privacy: .public)")
            return Self.message(for: updateStatus)
        }

        var attributes = baseQuery()
        attributes[kSecAttrAccount as String] = host
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        if addStatus != errSecSuccess {
            Self.logger.error("Keychain SecItemAdd failed (\(addStatus, privacy: .public)) for host \(host, privacy: .public)")
            return Self.message(for: addStatus)
        }
        // Defensive: read it back immediately. If we can't see what we just
        // wrote, the user denied the "Always Allow" prompt or the keychain is
        // locked — surface it so the failure isn't silent.
        if self.token(for: host) == nil {
            Self.logger.error("Keychain readback failed right after add for host \(host, privacy: .public)")
            return "Token saved but couldn't be read back from Keychain. Make sure you allowed Keychain access when macOS prompted."
        }
        Self.logger.info("Keychain wrote token for \(host, privacy: .public)")
        return nil
    }

    func removeToken(for host: String) {
        var query = baseQuery()
        query[kSecAttrAccount as String] = host
        _ = SecItemDelete(query as CFDictionary)
    }

    func hasToken(for host: String) -> Bool {
        token(for: host) != nil
    }

    /// Returns every host (Keychain `account`) that has a token stored under
    /// our service. Used by the clone picker to discover what the user
    /// actually has configured — instead of guessing `gitlab.com` when their
    /// real host is something self-hosted.
    func knownHosts() -> [String] {
        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            if status != errSecItemNotFound {
                Self.logger.error("Keychain enumerate failed (\(status, privacy: .public))")
            }
            return []
        }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
    }

    private static func message(for status: OSStatus) -> String {
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
        return "Keychain error \(status): \(detail)"
    }
}
