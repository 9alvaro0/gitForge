import SwiftUI

struct StashDetailHeader: View {
    let stash: Stash
    let onBack: () -> Void
    let onApply: () -> Void
    let onPop: () -> Void
    let onDrop: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(spacing: DesignTokens.Spacing.md) {
                GFButton(title: "← Back", size: .small, action: onBack)
                Spacer()
                GFButton(title: "Apply", size: .small, action: onApply)
                GFButton(title: "Pop", style: .primary, size: .small, action: onPop)
                OverflowMenu {
                    Button("Drop…", role: .destructive, action: onDrop)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.md) {
                Text(stash.subject)
                    .font(AppFont.sans(15, weight: .semibold))
                    .foregroundStyle(theme.palette.fg1)
                    .lineLimit(2)
                Spacer()
                MonoText(stash.reference, dim: true)
                MonoText(String(stash.sha.prefix(7)), dim: true)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xxxxl)
        .padding(.vertical, DesignTokens.Spacing.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.palette.bg2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.palette.lineStrong).frame(height: DesignTokens.Stroke.regular)
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    StashDetailHeader(
        stash: Stash.previewSamples[0],
        onBack: {}, onApply: {}, onPop: {}, onDrop: {}
    )
    .frame(width: 1100)
    .appTheme(theme)
}
