import Foundation

/// The blamed file cut into pseudo-hunks for `DiffSyntaxHighlighter`, which
/// colours diffs hunk by hunk: each chunk is a run of context lines whose
/// ids are the file's row indices, so the highlighter's result is keyed by
/// row.
nonisolated enum BlameHighlight {
    /// Lines per chunk: colour shows up a screen at a time instead of after
    /// the whole file, and a string or comment rarely spans a cut.
    static let chunkLines = 200

    static func chunks(of lines: [String], size: Int = chunkLines) -> [DiffHunk] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: lines.count, by: size).enumerated().map { index, start in
            let end = min(start + size, lines.count)
            let rows = (start..<end).map { row in
                DiffLine(id: row, kind: .context, content: lines[row], oldLineNumber: row + 1, newLineNumber: row + 1)
            }
            return DiffHunk(id: index, oldStart: start + 1, oldCount: rows.count, newStart: start + 1,
                            newCount: rows.count, header: "", lines: rows)
        }
    }
}
