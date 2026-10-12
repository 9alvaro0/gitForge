import Foundation

/// Builds a one-hunk patch for `git apply`, to stage, unstage or discard a
/// hunk — or only some of its lines — of one file.
///
/// Line selection follows git's own `add -p` editing rules. A patch applied
/// forward (stage: index ← worktree change) drops unselected `+` lines and
/// turns unselected `-` lines into context, since they stay in the target.
/// A patch applied with `--reverse` (unstage from the index, discard from the
/// worktree) does the opposite: unselected `+` lines are already in the
/// target, so they become context, and unselected `-` lines are dropped.
/// Header counts are left to `git apply --recount`.
nonisolated enum HunkPatch {
    /// `nil` when the selection keeps no change.
    static func make(path: String, hunk: DiffHunk, selectedLineIds: Set<Int>? = nil,
                     reverse: Bool = false) -> String? {
        var body: [String] = []
        var changes = 0
        var lastEmitted = false
        for line in hunk.lines {
            let selected = selectedLineIds?.contains(line.id) ?? true
            switch line.kind {
            case .context:
                body.append(" " + line.content)
                lastEmitted = true
            case .added:
                if selected {
                    body.append("+" + line.content)
                    changes += 1
                    lastEmitted = true
                } else if reverse {
                    body.append(" " + line.content)
                    lastEmitted = true
                } else {
                    lastEmitted = false
                }
            case .removed:
                if selected {
                    body.append("-" + line.content)
                    changes += 1
                    lastEmitted = true
                } else if reverse {
                    lastEmitted = false
                } else {
                    body.append(" " + line.content)
                    lastEmitted = true
                }
            case .noNewline:
                // Belongs to the line before it: kept only with that line.
                if lastEmitted { body.append("\\" + line.content) }
            }
        }
        guard changes > 0 else { return nil }
        let oldCount = body.filter { $0.hasPrefix(" ") || $0.hasPrefix("-") }.count
        let newCount = body.filter { $0.hasPrefix(" ") || $0.hasPrefix("+") }.count
        let header = [
            "diff --git a/\(path) b/\(path)",
            "--- a/\(path)",
            "+++ b/\(path)",
            "@@ -\(hunk.oldStart),\(oldCount) +\(hunk.newStart),\(newCount) @@",
        ]
        return (header + body).joined(separator: "\n") + "\n"
    }

    /// Whether `patch` has no context lines, which `git apply` only accepts
    /// with `--unidiff-zero` (diffs read with `-U0`).
    static func hasNoContext(_ patch: String) -> Bool {
        !patch.split(separator: "\n", omittingEmptySubsequences: false).contains { $0.hasPrefix(" ") }
    }
}
