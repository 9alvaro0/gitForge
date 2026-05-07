import Foundation
import os

/// Persistent list of hosts allowed to present otherwise-untrusted TLS
/// certificates (typical corporate / self-hosted GitLab instances). Only
/// affects requests originating from `RemoteAPI`.
///
/// Stored in `UserDefaults` so it survives launches without depending on
/// Keychain or extra config files. Keys are normalized to lowercase to
/// match what `RemoteHost` produces.
struct RemoteHostTrust: Sendable {
    static let shared = RemoteHostTrust()
    private static let logger = Logger(subsystem: "com.warwarelabs.gitForge", category: "trust")
    private let key = "com.warwarelabs.gitForge.trustedHosts"

    func trustedHosts() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func isTrusted(_ host: String) -> Bool {
        trustedHosts().contains(host.lowercased())
    }

    func setTrusted(_ host: String, _ trusted: Bool) {
        let normalized = host.lowercased()
        var list = trustedHosts()
        if trusted {
            if !list.contains(normalized) { list.append(normalized) }
        } else {
            list.removeAll { $0 == normalized }
        }
        UserDefaults.standard.set(list, forKey: key)
        Self.logger.info("Trust list updated; \(list.count, privacy: .public) hosts trusted")
    }
}
