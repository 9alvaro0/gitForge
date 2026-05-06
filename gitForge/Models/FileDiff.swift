import Foundation

/// A parsed unified diff for a single file. Pairs the parsed `[DiffHunk]`
/// (used by the diff viewer) with enough raw context to reconstruct a
/// partial patch when the user stages/unstages hunks individually.
nonisolated struct FileDiff: Sendable, Equatable {
    /// Lines that come before the first `@@` (e.g. `diff --git`, `index …`,
    /// `--- a/path`, `+++ b/path`). Required by `git apply`.
    let header: [String]
    /// Each hunk's full unified-diff text — `@@ … @@` line plus its body lines,
    /// in the same order as `hunks`. Index-aligned with `hunks`.
    let rawHunks: [String]
    let hunks: [DiffHunk]

    var isEmpty: Bool { hunks.isEmpty }

    static let empty = FileDiff(header: [], rawHunks: [], hunks: [])
}
