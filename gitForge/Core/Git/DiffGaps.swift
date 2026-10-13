import Foundation

/// Unchanged lines a diff leaves out between its hunks, before the first and
/// after the last: the "Show N hidden lines" rows. Lines are numbered on the
/// new side; the old side differs by a constant offset within a gap, since
/// nothing in it changed.
nonisolated struct DiffGap: Equatable, Sendable, Identifiable {
    /// Index of the hunk the gap precedes; `hunks.count` for the trailing one.
    let beforeHunk: Int
    /// 1-based new-side line numbers.
    let newLines: ClosedRange<Int>
    /// Old line number = new line number + `oldOffset`.
    let oldOffset: Int

    var id: Int { beforeHunk }
    var count: Int { newLines.count }

    /// The gap's lines as context `DiffLine`s, read from the new side of the
    /// file. Ids are the new line numbers, unique within the gap.
    func lines(from fileLines: [String]) -> [DiffLine] {
        newLines.compactMap { number in
            guard number - 1 < fileLines.count else { return nil }
            return DiffLine(id: number, kind: .context, content: fileLines[number - 1],
                            oldLineNumber: number + oldOffset, newLineNumber: number)
        }
    }
}

nonisolated enum DiffGaps {
    /// The gaps around `hunks` in a file whose new side has `newLineCount`
    /// lines. Empty without hunks: an all-context view isn't a diff.
    static func gaps(in hunks: [DiffHunk], newLineCount: Int) -> [DiffGap] {
        guard !hunks.isEmpty else { return [] }
        var gaps: [DiffGap] = []
        var nextNew = 1
        var nextOld = 1
        for (index, hunk) in hunks.enumerated() {
            let beforeNew = hunk.newCount == 0 ? hunk.newStart : hunk.newStart - 1
            let beforeOld = hunk.oldCount == 0 ? hunk.oldStart : hunk.oldStart - 1
            if beforeNew >= nextNew {
                gaps.append(DiffGap(beforeHunk: index, newLines: nextNew...beforeNew,
                                    oldOffset: beforeOld - beforeNew))
            }
            nextNew = after(start: hunk.newStart, count: hunk.newCount)
            nextOld = after(start: hunk.oldStart, count: hunk.oldCount)
        }
        if newLineCount >= nextNew {
            gaps.append(DiffGap(beforeHunk: hunks.count, newLines: nextNew...newLineCount,
                                oldOffset: nextOld - nextNew))
        }
        return gaps
    }

    /// First line after a hunk side. A zero-count side sits after line
    /// `start` instead of starting at it.
    private static func after(start: Int, count: Int) -> Int {
        count == 0 ? start + 1 : start + count
    }

    /// Text split into lines the way the diff parser sees them: a trailing
    /// newline doesn't make an extra empty line, and `\r` stays in content.
    static func splitLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        // By scalar, not Character: `\r\n` is one Character, so a
        // Character split would keep CRLF lines glued together.
        var lines = text.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false)
            .map { String(String.UnicodeScalarView($0)) }
        if text.unicodeScalars.last == "\n" { lines.removeLast() }
        return lines
    }

    /// Above this, expanding isn't offered: a whole generated file in memory
    /// for a few context lines isn't worth it.
    static let maxFileBytes = 2_000_000
}
