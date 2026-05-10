import Foundation

/// Centralised runtime toggles for verbose diagnostic logging. All default
/// to `false` so the Xcode console stays quiet during normal development —
/// Xcode attaches a debugger that surfaces every OSLog level, so dropping
/// noisy traces to `.debug` alone isn't enough; we have to skip the log
/// call entirely.
///
/// Each flag is backed by `UserDefaults` so it can be flipped without
/// recompiling, e.g.:
///   `defaults write com.warwarelabs.gitForge DiagnosticsTraceGitCommands -bool YES`
enum Diagnostics {
    /// Per-invocation `→ git …` / `✓ git …` trace from `GitCLI`. Keep off
    /// unless you're chasing a specific git interaction; the app fires
    /// dozens of commands per refresh, so the trace floods the console fast.
    /// `nonisolated` because `GitCLI` is a non-MainActor actor and reads
    /// this on every command — the project's default-MainActor isolation
    /// would otherwise force a hop on every call.
    nonisolated static var traceGitCommands: Bool {
        UserDefaults.standard.bool(forKey: "DiagnosticsTraceGitCommands")
    }
}
