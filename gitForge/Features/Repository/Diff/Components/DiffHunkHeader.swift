import SwiftUI

/// Shared by skeleton, unified, and split so the hunk strip stays in sync
/// wherever it appears.
struct DiffHunkHeader: View {
    let hunk: DiffHunk

    @Environment(\.appTheme) private var theme

    var body: some View {
        Text(hunk.header.isEmpty ? "@@" : hunk.header)
            .font(AppFont.font(.mono, monoFamily: theme.monoFont))
            .foregroundStyle(theme.colors.textQuaternary)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, Spacing.s12)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .background(theme.colors.info.opacity(0.07))
            .overlay(alignment: .top) {
                Rectangle().fill(theme.colors.separator).frame(height: 1)
            }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    DiffHunkHeader(hunk: DiffHunk.previewSamples[0])
        .frame(width: 520)
        .appTheme(theme)
}
