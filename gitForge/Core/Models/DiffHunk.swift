import Foundation

nonisolated struct DiffHunk: Sendable, Equatable, Identifiable, Hashable {
    let id: Int
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let header: String
    let lines: [DiffLine]
}

/// Why a `[DiffHunk]` array can be empty. Drives the DiffPane's empty-state
/// copy — without it, every "no `@@` produced" reason collapses into a flat
/// "No changes", which lies to the user when the file is genuinely modified
/// (binary, pure rename, mode-only, untracked-but-empty…).
nonisolated enum DiffEmptyState: Sendable, Equatable {
    /// Genuinely no diff content (clean file, or the engine has nothing to render).
    case empty
    /// Content exists but is binary — git emits `Binary files differ` and we
    /// synthesize nothing. Renderer shows a "Binary file" placeholder.
    case binary
    /// Untracked binary file — same visual as `.binary` but the copy hints
    /// "new file" so the user knows it isn't a tracked binary that changed.
    case untrackedBinary
    /// Pure rename / move with no content delta. The diff machinery returns
    /// metadata but no hunks; we surface it as such instead of "No changes".
    case renameOnly
}
