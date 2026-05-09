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
                Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                    ForEach(hunks) { hunk in
                        GridRow {
                            DiffHunkHeader(hunk: hunk)
                                .gridCellColumns(3)
                        }
                        let table = highlighted[hunk.id]
                        ForEach(Array(splitRows(for: hunk).enumerated()), id: \.offset) { _, row in
                            GridRow {
                                DiffSplitCell(line: row.left,  side: .left,  attributed: row.left.flatMap  { table?[$0.id] })
                                Rectangle()
                                    .fill(theme.palette.line)
                                    .frame(width: DesignTokens.Stroke.regular)
                                DiffSplitCell(line: row.right, side: .right, attributed: row.right.flatMap { table?[$0.id] })
                            }
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
