import SwiftUI

/// Split mode trades horizontal scroll for a stable two-column layout —
/// unified keeps the 2D scroll for full-line inspection. Both panels split
/// the viewport in half via a `Grid` pinned to the container width.
struct DiffSplitContent: View {
    let hunks: [DiffHunk]
    /// `hunk.id → line.id → AttributedString` from the parent's tokenisation.
    let highlighted: [Int: [Int: AttributedString]]

    @Environment(\.appTheme) private var theme

    var body: some View {
        GeometryReader { geo in
            ScrollView(.vertical) {
                // LazyVStack of HStack rows replaces the eager Grid so a diff
                // with thousands of rows doesn't realise every cell on first
                // paint. Trade-off vs. Grid: paired left/right cells align at
                // top (`.alignment(.top)`) instead of stretching to a shared
                // row height — if one side wraps further than the other, the
                // shorter side's background ends sooner. Acceptable: the line
                // numbers stay aligned and the visual cue (added/removed
                // tints) still carries.
                // Row offsets reset to 0 inside each hunk; compose with hunk
                // id so the LazyVStack sees globally-unique IDs (otherwise
                // SwiftUI logs "the ID … is used by multiple child views").
                LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.none) {
                    ForEach(hunks) { hunk in
                        DiffHunkHeader(hunk: hunk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("h-\(hunk.id)")
                        let table = highlighted[hunk.id]
                        ForEach(Array(splitRows(for: hunk).enumerated()), id: \.offset) { idx, row in
                            HStack(alignment: .top, spacing: DesignTokens.Spacing.none) {
                                DiffSplitCell(line: row.left,  side: .left,  attributed: row.left.flatMap  { table?[$0.id] })
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Rectangle()
                                    .fill(theme.palette.line)
                                    .frame(width: DesignTokens.Stroke.regular)
                                DiffSplitCell(line: row.right, side: .right, attributed: row.right.flatMap { table?[$0.id] })
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .id("h-\(hunk.id)-r-\(idx)")
                        }
                    }
                }
                .frame(width: geo.size.width, alignment: .topLeading)
            }
        }
    }
}

/// Pure function kept out of the View body so the body stays declarative.
private func splitRows(for hunk: DiffHunk) -> [SplitRow] {
    var out: [SplitRow] = []
    var pendingRemoved: [DiffLine] = []
    var pendingAdded: [DiffLine] = []

    func flush() {
        let count = max(pendingRemoved.count, pendingAdded.count)
        for i in 0..<count {
            out.append(SplitRow(
                left:  i < pendingRemoved.count ? pendingRemoved[i] : nil,
                right: i < pendingAdded.count   ? pendingAdded[i]   : nil
            ))
        }
        pendingRemoved.removeAll()
        pendingAdded.removeAll()
    }

    for line in hunk.lines {
        switch line.kind {
        case .context:
            flush()
            out.append(SplitRow(left: line, right: line))
        case .removed:
            pendingRemoved.append(line)
        case .added:
            pendingAdded.append(line)
        case .noNewline:
            flush()
            out.append(SplitRow(left: line, right: line))
        }
    }
    flush()
    return out
}

private struct SplitRow {
    let left: DiffLine?
    let right: DiffLine?
}

#Preview {
    @Previewable @State var theme = AppTheme()
    DiffSplitContent(hunks: DiffHunk.previewSamples, highlighted: [:])
        .frame(width: 720, height: 320)
        .background(theme.palette.bg2)
        .appTheme(theme)
}
