import Foundation

/// Throwaway `UserDefaults` suite for tests that need isolated preferences.
///
/// A plain suite name lives in `~/Library/Preferences/<suite>.plist`, and
/// cleaning it up from the test can't win: after `removePersistentDomain`
/// cfprefsd writes an empty plist back a few seconds later, even if the file
/// was deleted in between. So the suite name is an absolute path inside the
/// temporary directory instead — CFPreferences stores the domain at
/// `<path>.plist` and never touches the user's Preferences folder.
struct TestDefaults {
    let suiteName: String
    let defaults: UserDefaults

    init(prefix: String = "gitForge-tests") {
        suiteName = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
            .path
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create UserDefaults suite \(suiteName)")
        }
        self.defaults = defaults
    }

    /// Runs `body` against a fresh suite and removes it afterwards.
    static func with<T>(prefix: String = "gitForge-tests",
                        _ body: (TestDefaults) throws -> T) rethrows -> T {
        let suite = TestDefaults(prefix: prefix)
        defer { suite.remove() }
        return try body(suite)
    }

    /// Empties the domain and deletes its backing plist.
    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
        CFPreferencesAppSynchronize(suiteName as CFString)
        try? FileManager.default.removeItem(atPath: suiteName + ".plist")
    }
}
