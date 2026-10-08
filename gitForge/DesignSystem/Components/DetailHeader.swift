import SwiftUI

/// Header of a drill-in detail pane: a "← Back" row with trailing actions,
/// the pane's own title block below, and the shared chrome (padding, fill,
/// bottom rule). Stash and pull-request details used to duplicate it.
/// Titles inside `content` use `DesignTokens.Detail.titleFontSize`.
struct DetailHeader<Actions: View, Content: View>: View {
    let onBack: () -> Void
    @ViewBuilder let actions: Actions
    @ViewBuilder let content: Content

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(spacing: DesignTokens.Spacing.md) {
                GFButton(title: "← Back", size: .small, action: onBack)
                Spacer()
                actions
            }
            content
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
