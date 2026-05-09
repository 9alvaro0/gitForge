import SwiftUI

struct SettingsRowLabel: View {
    let text: String

    /// Shared so adjacent rows line up even when their controls have
    /// different intrinsic widths. Bumping this re-aligns the whole page.
    static let width: CGFloat = 130

    @Environment(\.appTheme) private var theme

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: FontSize.footnote, weight: .medium))
            .tracking(0.6)
            .foregroundStyle(theme.palette.fg3)
            .frame(width: Self.width, alignment: .leading)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
        SettingsRowLabel(text: "Name")
        SettingsRowLabel(text: "Default branch")
        SettingsRowLabel(text: "Pull strategy")
    }
    .padding(DesignTokens.Spacing.huge)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
