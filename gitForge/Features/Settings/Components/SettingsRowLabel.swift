import SwiftUI

struct SettingsRowLabel: View {
    let text: String

    /// Shared so adjacent rows line up even when their controls have
    /// different intrinsic widths. Bumping this re-aligns the whole page.
    static let width: CGFloat = 130

    @Environment(\.appTheme) private var theme

    var body: some View {
        Text(text)
            .textRole(.body)
            .foregroundStyle(theme.colors.textPrimary)
            .frame(width: Self.width, alignment: .leading)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(alignment: .leading, spacing: Spacing.s8) {
        SettingsRowLabel(text: "Name")
        SettingsRowLabel(text: "Default branch")
        SettingsRowLabel(text: "Pull strategy")
    }
    .padding(Spacing.s20)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
