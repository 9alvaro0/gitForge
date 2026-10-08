import Foundation

/// Read side of the user preferences the git layer depends on. `GitCLI` and
/// the view model read these at call time (straight from `UserDefaults`), so
/// Core never needs the UI-side `AppPreferences` object.
///
/// Every getter clamps to a sane range as a defence against stale or
/// hand-written `defaults write` values — a 0 or negative timeout/page size
/// silently bricks features (watchdog fires instantly, log loads nothing).
///
/// Keys keep their historical `appTheme.` prefix: these settings used to live
/// on `AppTheme`, and renaming the keys would reset every user's choices.
nonisolated enum GitPreferences {
    enum Keys {
        static let diffContext = "appTheme.diffContext"
        static let stashIncludeUntracked = "appTheme.stashIncludeUntracked"
        static let commitPageSize = "appTheme.commitPageSize"
        static let gitTimeout = "appTheme.gitTimeout"
    }

    static let diffContextRange = 0...100
    static let commitPageSizeRange = 50...5000
    static let gitTimeoutRange = 5...3600

    static let defaultDiffContextLines = 3
    static let defaultStashIncludeUntracked = true
    static let defaultCommitPageSize = 200
    static let defaultGitTimeoutSeconds = 60

    /// `git diff -U<n>` context lines.
    static var diffContextLines: Int {
        clamped(Keys.diffContext, default: defaultDiffContextLines, to: diffContextRange)
    }

    /// Whether quick stashes pass `--include-untracked`.
    static var stashIncludeUntracked: Bool {
        UserDefaults.standard.object(forKey: Keys.stashIncludeUntracked) as? Bool ?? defaultStashIncludeUntracked
    }

    /// `git log -n` per page.
    static var commitPageSize: Int {
        clamped(Keys.commitPageSize, default: defaultCommitPageSize, to: commitPageSizeRange)
    }

    /// Seconds without output before the watchdog kills a git subprocess.
    static var gitTimeoutSeconds: Int {
        clamped(Keys.gitTimeout, default: defaultGitTimeoutSeconds, to: gitTimeoutRange)
    }

    private static func clamped(_ key: String, default fallback: Int, to range: ClosedRange<Int>) -> Int {
        let raw = UserDefaults.standard.object(forKey: key) as? Int ?? fallback
        return min(max(raw, range.lowerBound), range.upperBound)
    }
}
