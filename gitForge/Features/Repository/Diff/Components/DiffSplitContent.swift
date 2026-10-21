import SwiftUI

/// Split mode trades horizontal scroll for a stable two-column layout —
/// unified keeps the 2D scroll for full-line inspection. Both panels split
/// the viewport in half via a `Grid` pinned to the container width.
struct DiffSplitContent: View {
    let hunks: [DiffHunk]
    /// `hunk.id → line.id → AttributedString` from the parent's tokenisation.
    let highlighted: [Int: [Int: AttributedString]]
    /// Hunk-level actions; picking single lines is a unified-view feature.
    var headerControls: (DiffHunk) -> DiffHunkHeader.Controls? = { _ in nil }
    /// Hidden-context gaps, as in the unified view.
    var gaps: [DiffGap] = []
    var expandedGaps: Set<Int> = []
    var fileLines: [String] = []
    var onExpandGap: (Int) -> Void = { _ in }
    /// Content under rows, full width, and the "+" on each half (pull requests).
    var lineAnnotations: DiffLineAnnotations? = nil

    @Environment(\.appTheme) private var theme

    var body: some View {
        GeometryReader { geo in
            ScrollView(.vertical) {
                // LazyVStack of HStack rows replaces the eager Grid so a diff
                // with thousands of rows doesn't realise every cell on first
                // paint. Each row sizes itself to its taller half (see the
                // `fixedSize` below), which is what the Grid used to do.
                // Row offsets reset to 0 inside each hunk; compose with hunk
                // id so the LazyVStack sees globally-unique IDs (otherwise
                // SwiftUI logs "the ID … is used by multiple child views").
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(hunks.enumerated()), id: \.element.id) { index, hunk in
                        gapSection(before: index)
                        DiffHunkHeader(hunk: hunk, controls: headerControls(hunk))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("h-\(hunk.id)")
                        let table = highlighted[hunk.id]
                        // As in the unified view: unchanged rows without
                        // annotations, one view per row with them.
                        if let lineAnnotations {
                            ForEach(Array(splitRows(for: hunk).enumerated()), id: \.offset) { idx, row in
                                VStack(alignment: .leading, spacing: 0) {
                                    rowCells(row, table: table, annotations: lineAnnotations)
                                    annotation(under: row, lineAnnotations)
                                }
                                .id("h-\(hunk.id)-r-\(idx)")
                            }
                        } else {
                            ForEach(Array(splitRows(for: hunk).enumerated()), id: \.offset) { idx, row in
                                rowCells(row, table: table, annotations: nil)
                                    .id("h-\(hunk.id)-r-\(idx)")
                            }
                        }
                    }
                    gapSection(before: hunks.count)
                }
                .frame(width: geo.size.width, alignment: .topLeading)
            }
        }
    }
}

extension DiffSplitContent {
    private func rowCells(_ row: SplitRow, table: [Int: AttributedString]?,
                          annotations: DiffLineAnnotations?) -> some View {
        HStack(alignment: .top, spacing: 0) {
            DiffSplitCell(line: row.left,  side: .left,  attributed: row.left.flatMap  { table?[$0.id] },
                          onAddComment: addComment(on: row.left, left: true, annotations))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Rectangle()
                .fill(theme.colors.separator)
                .frame(width: 1)
            DiffSplitCell(line: row.right, side: .right, attributed: row.right.flatMap { table?[$0.id] },
                          onAddComment: addComment(on: row.right, left: false, annotations))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        // Both halves stretch to the taller one, so a line
        // that wraps on one side keeps the other side's
        // tint or hatch the same height.
        .fixedSize(horizontal: false, vertical: true)
    }

    /// What goes under a row, across both halves.
    @ViewBuilder
    private func annotation(under row: SplitRow, _ annotations: DiffLineAnnotations) -> some View {
        let refs = annotations.matches(left: row.left, right: row.right)
        if !refs.isEmpty {
            annotations.content(refs)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The "+" on a half: it comments on that half's side.
    private func addComment(on line: DiffLine?, left: Bool, _ annotations: DiffLineAnnotations?) -> (() -> Void)? {
        guard let onAddComment = annotations?.onAddComment, let line,
              let side = DiffLineAnnotations.splitCommentSide(for: line, left: left) else { return nil }
        return { onAddComment(line, side) }
    }

    @ViewBuilder
    private func gapSection(before index: Int) -> some View {
        if let gap = gaps.first(where: { $0.beforeHunk == index }) {
            DiffGapSection(gap: gap, isExpanded: expandedGaps.contains(gap.id), fileLines: fileLines,
                           split: true, onExpand: { onExpandGap(gap.id) })
                .id("g-\(gap.id)")
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
        .background(theme.colors.bgCode)
        .appTheme(theme)
}
