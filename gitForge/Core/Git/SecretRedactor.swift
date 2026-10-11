import Foundation

/// Account tokens handed to git this session, so `GitCLI.redacted` blanks
/// them out of logs and error messages even if a server or a hook echoes
/// one back (spec §6).
nonisolated final class SecretRedactor: @unchecked Sendable {
    static let shared = SecretRedactor()

    private let lock = NSLock()
    private var secrets: Set<String> = []

    /// Values under 8 characters are ignored: blanking them would mangle
    /// ordinary text, and no real token is that short.
    func register(_ secret: String) {
        guard secret.count >= 8 else { return }
        _ = lock.withLock { secrets.insert(secret) }
    }

    func redact(_ text: String) -> String {
        let current = lock.withLock { secrets }
        return current.reduce(text) { $0.replacingOccurrences(of: $1, with: "****") }
    }
}
