import SwiftUI

/// The two-level VStack is intentional. The inner stack is `.fixedSize`
/// vertically so rows keep their natural height (no stretching when the
/// diff is short). The outer stack extends to the viewport with a trailing
/// Spacer that anchors the content to the top — preventing the bidirectional
/// ScrollView from centring it.
struct DiffUnifiedContent: View {
    let hunks: [DiffHunk]
    /// `hunk.id → line.id → AttributedString` from the parent's tokenisation.
    let highlighted: [Int: [Int: AttributedString]]
    /// `hunk.id → picked line ids`, and the hunk actions per header; empty
    /// / nil outside Changes.
    var selectedLines: [Int: Set<Int>] = [:]
    var onToggleLine: ((DiffHunk, DiffLine) -> Void)? = nil
    var headerControls: (DiffHunk) -> DiffHunkHeader.Controls? = { _ in nil }
    /// Hidden-context gaps (empty when the file's new side isn't loaded).
    var gaps: [DiffGap] = []
    var expandedGaps: Set<Int> = []
    var fileLines: [String] = []
    var onExpandGap: (Int) -> Void = { _ in }

    @Environment(\.appPreferences) private var preferences

    var body: some View {
        // Wrapped lines must be measured against the viewport, so the
        // horizontal axis only scrolls when lines overflow instead.
        let wrap = preferences.diffWrapLongLines
        GeometryReader { geo in
            ScrollView(wrap ? [.vertical] : [.vertical, .horizontal]) {
                // LazyVStack at the outer level so a diff of 50k lines doesn't
                // materialise every DiffRow at first paint. Hunks are usually
                // small (<1k lines each) so the inner ForEach stays eager —
                // the win is letting the scroll view skip hunks above/below
                // the viewport entirely.
                // Inner line.id is local to its hunk (0,1,2…), so without
                // composing it with `hunk.id` the LazyVStack sees the same
                // ID across multiple hunks and SwiftUI logs "the ID … is
                // used by multiple child views".
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(hunks.enumerated()), id: \.element.id) { index, hunk in
                        gapSection(before: index)
                        DiffHunkHeader(hunk: hunk, controls: headerControls(hunk))
                            .id("h-\(hunk.id)")
                        let table = highlighted[hunk.id]
                        let picked = selectedLines[hunk.id] ?? []
                        ForEach(hunk.lines) { line in
                            DiffRow(line: line, attributed: table?[line.id],
                                    isSelected: picked.contains(line.id),
                                    onToggle: toggle(line, in: hunk))
                                .id("h-\(hunk.id)-l-\(line.id)")
                        }
                    }
                    gapSection(before: hunks.count)
                }
                .frame(minWidth: geo.size.width, maxWidth: wrap ? geo.size.width : nil,
                       minHeight: geo.size.height, alignment: .topLeading)
            }
        }
    }
}

extension DiffUnifiedContent {
    @ViewBuilder
    private func gapSection(before index: Int) -> some View {
        if let gap = gaps.first(where: { $0.beforeHunk == index }) {
            DiffGapSection(gap: gap, isExpanded: expandedGaps.contains(gap.id), fileLines: fileLines,
                           onExpand: { onExpandGap(gap.id) })
                .id("g-\(gap.id)")
        }
    }

    /// Only added and removed lines can be picked.
    private func toggle(_ line: DiffLine, in hunk: DiffHunk) -> (() -> Void)? {
        guard let onToggleLine, line.kind == .added || line.kind == .removed else { return nil }
        return { onToggleLine(hunk, line) }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    DiffUnifiedContent(hunks: DiffHunk.previewSamples, highlighted: [:])
        .frame(width: 720, height: 320)
        .background(theme.colors.bgCode)
        .appTheme(theme)
}
