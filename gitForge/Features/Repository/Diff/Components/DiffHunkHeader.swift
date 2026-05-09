import SwiftUI

/// Shared by skeleton, unified, and split so the hunk strip stays in sync
/// wherever it appears.
struct DiffHunkHeader: View {
    let hunk: DiffHunk

    @Environment(\.appTheme) private var theme

    var body: some View {
        Text(hunk.header.isEmpty ? "@@" : hunk.header)
            .font(AppFont.mono(11, family: theme.monoFont))
            .foregroundStyle(theme.palette.fg3)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, DesignTokens.Spacing.xxl)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.palette.bg3)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(theme.palette.line)
                    .frame(height: DesignTokens.Stroke.regular)
            }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    DiffHunkHeader(hunk: DiffHunk.previewSamples[0])
        .frame(width: 520)
        .background(theme.palette.bg2)
        .appTheme(theme)
}
