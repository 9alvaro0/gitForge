import SwiftUI

/// Renders a real-looking hunk shape under `.skeleton(true)` so the layout
/// doesn't pop when the actual diff arrives — same row metrics, same gutter,
/// same hunk strip.
struct DiffLoadingSkeleton: View {
    var body: some View {
        GeometryReader { geo in
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.none) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.none) {
                        DiffHunkHeader(hunk: Self.placeholderHunk)
                        ForEach(Self.placeholderHunk.lines) { line in
                            DiffRow(line: line, attributed: nil)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
            }
        }
        .skeleton(true)
    }

    private static let placeholderHunk = DiffHunk(
        id: 0,
        oldStart: 1, oldCount: 7, newStart: 1, newCount: 8,
        header: "@@ -1,7 +1,8 @@ func loadData() {",
        lines: [
            DiffLine(id: 0, kind: .context, content: "    func loadData() async throws {",                      oldLineNumber: 1,    newLineNumber: 1),
            DiffLine(id: 1, kind: .context, content: "        let token = credentials.token(for: host)",        oldLineNumber: 2,    newLineNumber: 2),
            DiffLine(id: 2, kind: .removed, content: "        guard token != nil else { return }",              oldLineNumber: 3,    newLineNumber: nil),
            DiffLine(id: 3, kind: .added,   content: "        guard let token else { return }",                 oldLineNumber: nil,  newLineNumber: 3),
            DiffLine(id: 4, kind: .context, content: "        let response = try await fetcher.fetch()",        oldLineNumber: 4,    newLineNumber: 4),
            DiffLine(id: 5, kind: .added,   content: "        items = response.items",                          oldLineNumber: nil,  newLineNumber: 5),
            DiffLine(id: 6, kind: .added,   content: "        lastSync = Date()",                               oldLineNumber: nil,  newLineNumber: 6),
            DiffLine(id: 7, kind: .context, content: "        return items",                                    oldLineNumber: 5,    newLineNumber: 7),
            DiffLine(id: 8, kind: .context, content: "    }",                                                   oldLineNumber: 6,    newLineNumber: 8),
        ]
    )
}

#Preview {
    @Previewable @State var theme = AppTheme()
    DiffLoadingSkeleton()
        .frame(width: 720, height: 320)
        .background(theme.palette.bg2)
        .appTheme(theme)
}
