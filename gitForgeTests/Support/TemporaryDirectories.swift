import Foundation

/// Temporary directories for tests, removed when the test process exits.
/// Tests that never cleaned up after themselves left thousands of account
/// stores and repositories in the user's temporary folder.
nonisolated enum TemporaryDirectories {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var urls: [URL] = []
    nonisolated(unsafe) private static var installed = false

    /// A fresh path under the temporary folder (not created), removed at exit.
    static func make(_ prefix: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        register(url)
        return url
    }

    /// Removes `url` at exit too (for paths made elsewhere).
    static func register(_ url: URL) {
        lock.withLock {
            urls.append(url)
            if !installed {
                installed = true
                atexit { TemporaryDirectories.removeAll() }
            }
        }
    }

    private static func removeAll() {
        let pending = lock.withLock { urls }
        for url in pending { try? FileManager.default.removeItem(at: url) }
    }
}
