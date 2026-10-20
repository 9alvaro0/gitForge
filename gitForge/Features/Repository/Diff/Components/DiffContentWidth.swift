import AppKit

/// Width the unified diff needs to show its longest line in full.
///
/// The rows sit in a `LazyVStack`, which sizes itself only to the rows laid
/// out so far: with a long line off screen, the horizontal scroll stopped
/// short of its end. Measuring the lines up front gives the stack the width
/// of the widest one, wherever it is.
nonisolated enum DiffContentWidth {
    /// The parts of a `DiffRow` around the code: two line numbers, the sign
    /// and the code's trailing padding.
    @MainActor
    static let unifiedChrome: CGFloat =
        (DiffGutter.unifiedNumber + DiffGutter.numberTrailing) * 2 + DiffGutter.unifiedSign + Spacing.s12

    /// Lines measured exactly; the rest are ruled out by their estimate.
    static let measuredCandidates = 16

    /// Full row width for `candidates` (from `widestCandidates`) in the
    /// code font, chrome included. `0` with no lines.
    @MainActor
    static func unifiedRowWidth(of candidates: [String], font: NSFont) -> CGFloat {
        guard !candidates.isEmpty else { return 0 }
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let code = candidates
            .map { NSAttributedString(string: $0, attributes: attributes).size().width }
            .max() ?? 0
        // One character of slack: a bold run or rounding shouldn't clip the
        // last glyph. Too wide only leaves a little blank space.
        let slack = font.maximumAdvancement.width
        return ceil(code + slack + unifiedChrome)
    }

    /// The `limit` lines likeliest to be widest, by `estimatedColumns`,
    /// widest first. Pure and off the main actor: it walks every character.
    static func widestCandidates(_ lines: [String], limit: Int = measuredCandidates) -> [String] {
        guard limit > 0 else { return [] }
        var kept: [(columns: Int, line: String)] = []
        for line in lines {
            let columns = estimatedColumns(line)
            if kept.count == limit {
                guard columns > kept[kept.count - 1].columns else { continue }
                kept.removeLast()
            }
            let index = kept.firstIndex { $0.columns < columns } ?? kept.endIndex
            kept.insert((columns, line), at: index)
        }
        return kept.map(\.line)
    }

    /// Rough width in monospaced columns: tabs count as a full tab stop and
    /// wide (CJK, emoji) characters as two, so the exact measurement isn't
    /// skipped for a line that looks short but renders wide.
    static func estimatedColumns(_ line: String) -> Int {
        var columns = 0
        for scalar in line.unicodeScalars {
            switch scalar.value {
            case 0x09: columns += 8
            case 0..<0x1100: columns += 1
            default: columns += 2
            }
        }
        return columns
    }
}
