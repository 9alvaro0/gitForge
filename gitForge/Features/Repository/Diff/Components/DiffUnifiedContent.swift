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
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.none) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.none) {
                        ForEach(hunks) { hunk in
                            DiffHunkHeader(hunk: hunk)
                            let table = highlighted[hunk.id]
                            ForEach(hunk.lines) { line in
                                DiffRow(line: line, attributed: table?[line.id])
                            }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
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
