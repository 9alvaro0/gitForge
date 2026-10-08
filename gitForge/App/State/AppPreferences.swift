import SwiftUI
import Observation

/// Behaviour and presentation preferences edited in Settings: diff layout,
/// date format, git timeouts, confirmations. Split out of `AppTheme`, which
/// now only describes how the app *looks*. One instance lives in
/// `WorkspaceUI` and is injected via `\.appPreferences`.
///
/// The git-facing values are written under `GitPreferences.Keys`, which is
/// where `GitCLI` reads them back from.
@Observable
@MainActor
final class AppPreferences {
    /// Default diff layout that History / Staging / Stashes seed their local
    /// toggle from. Per-view toggles stay ephemeral, so changing this in
    /// Settings is the only way to flip the starting mode globally.
    var defaultDiffMode: DiffPane.ViewMode {
        didSet { defaults.set(defaultDiffMode.rawValue, forKey: Keys.diffMode) }
    }
    /// When `true`, long lines in the diff view wrap instead of overflowing
    /// horizontally. Off by default — matches GitHub/Tower defaults.
    var diffWrapLongLines: Bool {
        didSet { defaults.set(diffWrapLongLines, forKey: Keys.diffWrap) }
    }
    /// How history / pulls / branches surface dates: relative ("2h ago") or
    /// absolute ("2026-05-09 14:32").
    var dateDisplayMode: DateDisplayMode {
        didSet { defaults.set(dateDisplayMode.rawValue, forKey: Keys.dateMode) }
    }
    /// When `true`, "Force push" asks for confirmation first. Default on —
    /// `--force-with-lease` is safer than bare `--force` but it still
    /// rewrites remote history.
    var confirmForcePush: Bool {
        didSet { defaults.set(confirmForcePush, forKey: Keys.confirmForcePush) }
    }
    /// Unchanged context lines around each diff hunk (`git diff -U<n>`).
    var diffContextLines: Int {
        didSet { defaults.set(diffContextLines, forKey: GitPreferences.Keys.diffContext) }
    }
    /// When `true`, quick stashes pass `--include-untracked`. Default on —
    /// losing untracked files because a stash skipped them is the more
    /// painful failure mode.
    var stashIncludeUntracked: Bool {
        didSet { defaults.set(stashIncludeUntracked, forKey: GitPreferences.Keys.stashIncludeUntracked) }
    }
    /// `git log -n <commitPageSize>` per page. Bigger = fewer round-trips on
    /// huge repos at the cost of a slower first paint.
    var commitPageSize: Int {
        didSet { defaults.set(commitPageSize, forKey: GitPreferences.Keys.commitPageSize) }
    }
    /// Seconds without output before a git subprocess is killed.
    var gitTimeoutSeconds: Int {
        didSet { defaults.set(gitTimeoutSeconds, forKey: GitPreferences.Keys.gitTimeout) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaultDiffMode = defaults.string(forKey: Keys.diffMode)
            .flatMap(DiffPane.ViewMode.init(rawValue:)) ?? .unified
        diffWrapLongLines = defaults.object(forKey: Keys.diffWrap) as? Bool ?? false
        dateDisplayMode = defaults.string(forKey: Keys.dateMode)
            .flatMap(DateDisplayMode.init(rawValue:)) ?? .relative
        confirmForcePush = defaults.object(forKey: Keys.confirmForcePush) as? Bool ?? true
        diffContextLines = defaults.object(forKey: GitPreferences.Keys.diffContext) as? Int
            ?? GitPreferences.defaultDiffContextLines
        stashIncludeUntracked = defaults.object(forKey: GitPreferences.Keys.stashIncludeUntracked) as? Bool
            ?? GitPreferences.defaultStashIncludeUntracked
        commitPageSize = defaults.object(forKey: GitPreferences.Keys.commitPageSize) as? Int
            ?? GitPreferences.defaultCommitPageSize
        gitTimeoutSeconds = defaults.object(forKey: GitPreferences.Keys.gitTimeout) as? Int
            ?? GitPreferences.defaultGitTimeoutSeconds
    }

    /// Historical `appTheme.` keys, kept so existing choices survive the move.
    private enum Keys {
        static let diffMode = "appTheme.diffMode"
        static let diffWrap = "appTheme.diffWrap"
        static let confirmForcePush = "appTheme.confirmForcePush"
        static let dateMode = "appTheme.dateMode"
    }
}

private struct AppPreferencesKey: EnvironmentKey {
    @MainActor static let defaultValue: AppPreferences = AppPreferences()
}

extension EnvironmentValues {
    var appPreferences: AppPreferences {
        get { self[AppPreferencesKey.self] }
        set { self[AppPreferencesKey.self] = newValue }
    }
}

extension View {
    func appPreferences(_ preferences: AppPreferences) -> some View {
        environment(\.appPreferences, preferences)
    }
}
