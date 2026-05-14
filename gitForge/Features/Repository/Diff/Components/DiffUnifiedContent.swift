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

    var body: some View {
        GeometryReader { geo in
            ScrollView([.vertical, .horizontal]) {
                // LazyVStack at the outer level so a diff of 50k lines doesn't
                // materialise every DiffRow at first paint. Hunks are usually
                // small (<1k lines each) so the inner ForEach stays eager —
                // the win is letting the scroll view skip hunks above/below
                // the viewport entirely.
                LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.none, pinnedViews: []) {
                    ForEach(hunks) { hunk in
                        DiffHunkHeader(hunk: hunk)
                        let table = highlighted[hunk.id]
                        ForEach(hunk.lines) { line in
                            DiffRow(line: line, attributed: table?[line.id])
                        }
                    }
                }
                .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
            }
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    DiffUnifiedContent(hunks: DiffHunk.previewSamples, highlighted: [:])
        .frame(width: 720, height: 320)
        .background(theme.palette.bg2)
        .appTheme(theme)
}
