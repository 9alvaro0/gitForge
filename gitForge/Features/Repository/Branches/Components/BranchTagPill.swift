import SwiftUI

/// Single tag chip with a `Push to origin` / `Delete…` menu. Used by
/// `BranchTagsSection` inside the Branches view.
struct BranchTagPill: View {
    let tag: GitRef
    let onPush: (GitRef) -> Void
    let onDelete: (GitRef) -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        Menu {
            Button("Push to origin") { onPush(tag) }
            Divider()
            Button("Delete…", role: .destructive) { onDelete(tag) }
        } label: {
            HStack(spacing: DesignTokens.Spacing.sm) {
                GFIcon(kind: .tag, size: 10, stroke: theme.palette.mod)
                Text(tag.name).font(AppFont.mono(11.5, family: theme.monoFont))
            }
            .foregroundStyle(theme.palette.mod)
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                    .fill(theme.palette.mod.opacity(DesignTokens.Opacity.subtle))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                    .stroke(theme.palette.mod.opacity(DesignTokens.Opacity.strong),
                            lineWidth: DesignTokens.Stroke.regular)
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    BranchTagPill(tag: .previewTag, onPush: { _ in }, onDelete: { _ in })
        .padding()
        .background(theme.palette.bg2)
        .appTheme(theme)
}
