import SwiftUI

/// "Uncommitted changes" row pinned to the top of the log when the working
/// tree is dirty. Mirrors the column layout of a real `CommitRow` so the
/// graph gutter and column boundaries line up.
struct UncommittedRow: View {
    let rowHeight: CGFloat
    let gutterWidth: CGFloat
    let columns: ResizableTableModel

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.none) {
            HStack(spacing: DesignTokens.Spacing.none) {
                Spacer().frame(width: DesignTokens.IconSize.xl)
                Rectangle().fill(theme.palette.mod).frame(width: DesignTokens.Spacing.md, height: DesignTokens.Spacing.md)
                    .overlay(Rectangle().stroke(theme.palette.mod, lineWidth: DesignTokens.Stroke.regular))
            }
            .frame(width: gutterWidth, alignment: .leading)
            Color.clear.frame(width: DesignTokens.Spacing.md)
            Color.clear.frame(width: columns.width("branchTag"))
            Color.clear.frame(width: DesignTokens.Spacing.md)
            HStack(spacing: DesignTokens.Spacing.md) {
                Circle().fill(theme.palette.mod).frame(width: DesignTokens.Spacing.md, height: DesignTokens.Spacing.md)
                Text("Uncommitted changes")
                    .font(AppFont.sans(12.5))
                    .italic()
                    .foregroundStyle(theme.palette.mod)
            }
            .frame(width: columns.width("message"), alignment: .leading)
            Color.clear.frame(width: DesignTokens.Spacing.md)
            Text("").frame(width: columns.width("author"))
            Color.clear.frame(width: DesignTokens.Spacing.md)
            Text("–")
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
                .frame(width: columns.width("sha"), alignment: .leading)
            Color.clear.frame(width: DesignTokens.Spacing.md)
            Text("now")
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
                .frame(width: columns.width("when"), alignment: .trailing)
            Color.clear.frame(width: DesignTokens.Spacing.md)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignTokens.Spacing.xxxxl)
        .frame(height: rowHeight)
        .background(LinearGradient(colors: [theme.palette.mod.opacity(DesignTokens.Opacity.faint), .clear], startPoint: .leading, endPoint: .trailing))
    }
}
