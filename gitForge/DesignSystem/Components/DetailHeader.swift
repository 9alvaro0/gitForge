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
        VStack(alignment: .leading, spacing: Spacing.s8) {
            HStack(spacing: Spacing.s8) {
                GFButton(title: "Back", systemImage: "chevron.left", size: .small, action: onBack)
                Spacer()
                actions
            }
            content
        }
        .padding(.horizontal, Spacing.s20)
        .padding(.vertical, Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.bgContent)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.colors.separator).frame(height: 1)
        }
    }
}
