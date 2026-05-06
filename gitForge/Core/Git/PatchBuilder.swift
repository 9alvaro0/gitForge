import Foundation

/// Reconstructs a unified diff containing only a chosen subset of hunks
/// from a previously parsed `FileDiff`. The output can be fed straight into
/// `git apply --cached` (stage) or `git apply --cached --reverse` (unstage).
///
/// Note: every hunk in a unified diff already references absolute line
/// numbers in the original/new file via `@@ -X,Y +A,B @@`, so applying a
/// proper subset of consecutive hunks works without recomputing offsets.
enum PatchBuilder {
    /// Build a partial patch from `diff` keeping only the hunks whose `id`
    /// is in `hunkIds`. Returns `nil` if the resulting patch would be empty
    /// (no hunks selected, or no header to anchor it on).
    static func makePatch(from diff: FileDiff, hunkIds: Set<Int>) -> String? {
        guard !diff.header.isEmpty else { return nil }
        guard !hunkIds.isEmpty else { return nil }

        var pieces: [String] = []
        pieces.append(diff.header.joined(separator: "\n"))
        for (idx, hunk) in diff.hunks.enumerated() where hunkIds.contains(hunk.id) {
            pieces.append(diff.rawHunks[idx])
        }
        if pieces.count == 1 { return nil }
        // git apply expects a trailing newline.
        return pieces.joined(separator: "\n") + "\n"
    }
}
