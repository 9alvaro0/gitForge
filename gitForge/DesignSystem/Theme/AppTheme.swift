import SwiftUI
import Observation

/// Active theme + user prefs. One instance lives in `AppState` and is injected via Environment.
@Observable
@MainActor
final class AppTheme {
    var mode: ThemeMode {
        didSet {
            persist(); refreshPalette()
        }
    }
    var accent: Color {
        didSet { persistAccent(); refreshPalette() }
    }
    var density: Density {
        didSet { persistDensity() }
    }
    var monoFont: MonoFontFamily {
        didSet { persistMonoFont() }
    }
    /// Default diff layout that History / Staging / Conflicts seed their
    /// local toggle from. Per-view toggles stay ephemeral so changing this
    /// in Settings is the only way to flip the starting mode globally.
    var defaultDiffMode: DiffPane.ViewMode {
        didSet { persistDiffMode() }
    }
    /// When `true`, long lines in the diff view wrap instead of overflowing
    /// horizontally. Off by default — matches GitHub/Tower defaults.
    var diffWrapLongLines: Bool {
        didSet { persistDiffWrap() }
    }
    /// Number of unchanged context lines around each diff hunk
    /// (`git diff -U<n>`). Default 3 matches git's own default.
    var diffContextLines: Int {
        didSet { persistDiffContext() }
    }
    /// When `true`, hitting "Force push" pops a confirmation dialog before
    /// the push fires. Default on — `--force-with-lease` is safer than bare
    /// `--force` but it still rewrites remote history.
    var confirmForcePush: Bool {
        didSet { persistConfirmForcePush() }
    }
    /// When `true`, the toolbar Stash button (and Stash All menu) pass
    /// `--include-untracked` to git. Default on — losing untracked files
    /// because a quick stash skipped them is the more painful failure mode.
    var stashIncludeUntracked: Bool {
        didSet { persistStashIncludeUntracked() }
    }
    /// How history / pulls / branches surface dates: relative ("2h ago")
    /// or absolute ("2026-05-09 14:32"). Default relative — that's what
    /// existed before the toggle.
    var dateDisplayMode: DateDisplayMode {
        didSet { persistDateDisplayMode() }
    }
    /// `git log -n <commitPageSize>` per page. Bigger = fewer round-trips
    /// on huge repos at the cost of slower first paint.
    var commitPageSize: Int {
        didSet { persistCommitPageSize() }
    }
    /// Watchdog timeout (seconds) before the `git` subprocess is killed.
    /// 60 is the default; users on slow networks or with large repos may
    /// want to push it higher. `GitCLI` reads it directly from disk.
    var gitTimeoutSeconds: Int {
        didSet { persistGitTimeout() }
    }
    /// Live `ColorScheme` reported by the OS. The shell view keeps this in
    /// sync via `.onChange(of: \.colorScheme)`. Read by `effectiveMode` so
    /// `.system` resolves to the right palette without forcing a scheme.
    var systemColorScheme: ColorScheme = .dark {
        didSet { if mode == .system { refreshPalette() } }
    }

    /// `mode` after collapsing `.system` to whatever the OS reports. Use
    /// this anywhere a binary dark/light decision is needed.
    var effectiveMode: ThemeMode {
        if mode != .system { return mode }
        return systemColorScheme == .dark ? .dark : .light
    }

    private(set) var palette: ThemePalette = .dark

    static let accentSwatches: [Color] = [
        Color(hex: 0x7c5cff),
        Color(hex: 0x56b497),
        Color(hex: 0xff7e6b),
        Color(hex: 0x5da4ff),
    ]

    init() {
        let savedMode = UserDefaults.standard.string(forKey: Keys.mode).flatMap(ThemeMode.init(rawValue:)) ?? .system
        let savedDensity = UserDefaults.standard.string(forKey: Keys.density).flatMap(Density.init(rawValue:)) ?? .regular
        let savedMonoRaw = UserDefaults.standard.string(forKey: Keys.monoFont) ?? MonoFontFamily.systemMono.rawValue
        let savedMono = (MonoFontFamily(rawValue: savedMonoRaw)?.resolved()) ?? .systemMono
        let savedAccent = UserDefaults.standard.string(forKey: Keys.accent).flatMap(Color.init(stringHex:)) ?? Color(hex: 0x7c5cff)
        let savedDiffMode = UserDefaults.standard.string(forKey: Keys.diffMode)
            .flatMap(DiffPane.ViewMode.init(rawValue:)) ?? .unified
        let savedWrap = UserDefaults.standard.object(forKey: Keys.diffWrap) as? Bool ?? false
        let savedContext = UserDefaults.standard.object(forKey: Keys.diffContext) as? Int ?? 3
        let savedConfirmForce = UserDefaults.standard.object(forKey: Keys.confirmForcePush) as? Bool ?? true
        let savedStashUntracked = UserDefaults.standard.object(forKey: Keys.stashIncludeUntracked) as? Bool ?? true
        let savedDateMode = UserDefaults.standard.string(forKey: Keys.dateMode).flatMap(DateDisplayMode.init(rawValue:)) ?? .relative
        let savedPageSize = UserDefaults.standard.object(forKey: Keys.commitPageSize) as? Int ?? 200
        let savedTimeout = UserDefaults.standard.object(forKey: Keys.gitTimeout) as? Int ?? 60

        self.mode = savedMode
        self.accent = savedAccent
        self.density = savedDensity
        self.monoFont = savedMono
        self.defaultDiffMode = savedDiffMode
        self.diffWrapLongLines = savedWrap
        self.diffContextLines = savedContext
        self.confirmForcePush = savedConfirmForce
        self.stashIncludeUntracked = savedStashUntracked
        self.dateDisplayMode = savedDateMode
        self.commitPageSize = savedPageSize
        self.gitTimeoutSeconds = savedTimeout
        refreshPalette()
    }

    func toggleMode() {
        mode = (effectiveMode == .dark) ? .light : .dark
    }

    private func refreshPalette() {
        palette = ThemePalette.palette(for: effectiveMode, accent: accent)
    }

    private func persist() {
        UserDefaults.standard.set(mode.rawValue, forKey: Keys.mode)
    }
    private func persistDensity() {
        UserDefaults.standard.set(density.rawValue, forKey: Keys.density)
    }
    private func persistMonoFont() {
        UserDefaults.standard.set(monoFont.rawValue, forKey: Keys.monoFont)
    }
    private func persistAccent() {
        UserDefaults.standard.set(accent.hexString, forKey: Keys.accent)
    }
    private func persistDiffMode() {
        UserDefaults.standard.set(defaultDiffMode.rawValue, forKey: Keys.diffMode)
    }
    private func persistDiffWrap() {
        UserDefaults.standard.set(diffWrapLongLines, forKey: Keys.diffWrap)
    }
    private func persistDiffContext() {
        UserDefaults.standard.set(diffContextLines, forKey: Keys.diffContext)
    }
    private func persistConfirmForcePush() {
        UserDefaults.standard.set(confirmForcePush, forKey: Keys.confirmForcePush)
    }
    private func persistStashIncludeUntracked() {
        UserDefaults.standard.set(stashIncludeUntracked, forKey: Keys.stashIncludeUntracked)
    }
    private func persistDateDisplayMode() {
        UserDefaults.standard.set(dateDisplayMode.rawValue, forKey: Keys.dateMode)
    }
    private func persistCommitPageSize() {
        UserDefaults.standard.set(commitPageSize, forKey: Keys.commitPageSize)
    }
    private func persistGitTimeout() {
        UserDefaults.standard.set(gitTimeoutSeconds, forKey: Keys.gitTimeout)
    }

    /// Numeric default exposed for code paths that can't easily inject the
    /// active `AppTheme` (currently the `GitCLI` diff helpers, which read
    /// the persisted value directly so we don't have to thread the prefs
    /// store through every CLI call). `nonisolated` because it only touches
    /// `UserDefaults`, never the `AppTheme` instance.
    /// All persisted-int getters clamp to a sane range as a defence against
    /// stale or hand-written `defaults write` values — a 0 or negative
    /// timeout/page-size silently bricks features (watchdog fires instantly,
    /// log loads zero commits).
    nonisolated static func persistedDiffContextLines() -> Int {
        let raw = UserDefaults.standard.object(forKey: Keys.diffContext) as? Int ?? 3
        return min(max(raw, 0), 100)
    }

    /// Same escape hatch as `persistedDiffContextLines` — `RepositoryViewModel`
    /// reads it from the stash code path so we don't have to wire the theme
    /// through the view-model layer.
    nonisolated static func persistedStashIncludeUntracked() -> Bool {
        UserDefaults.standard.object(forKey: Keys.stashIncludeUntracked) as? Bool ?? true
    }
    nonisolated static func persistedCommitPageSize() -> Int {
        let raw = UserDefaults.standard.object(forKey: Keys.commitPageSize) as? Int ?? 200
        return min(max(raw, 50), 5000)
    }
    nonisolated static func persistedGitTimeoutSeconds() -> Int {
        let raw = UserDefaults.standard.object(forKey: Keys.gitTimeout) as? Int ?? 60
        return min(max(raw, 5), 3600)
    }

    private nonisolated enum Keys {
        static let mode = "appTheme.mode"
        static let density = "appTheme.density"
        static let accent = "appTheme.accent"
        static let monoFont = "appTheme.monoFont"
        static let diffMode = "appTheme.diffMode"
        static let diffWrap = "appTheme.diffWrap"
        static let diffContext = "appTheme.diffContext"
        static let confirmForcePush = "appTheme.confirmForcePush"
        static let stashIncludeUntracked = "appTheme.stashIncludeUntracked"
        static let dateMode = "appTheme.dateMode"
        static let commitPageSize = "appTheme.commitPageSize"
        static let gitTimeout = "appTheme.gitTimeout"
    }
}

private extension Color {
    init?(stringHex: String) {
        var s = stringHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(hex: v)
    }

    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .clear
        let r = Int(round(Double(ns.redComponent) * 255))
        let g = Int(round(Double(ns.greenComponent) * 255))
        let b = Int(round(Double(ns.blueComponent) * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
