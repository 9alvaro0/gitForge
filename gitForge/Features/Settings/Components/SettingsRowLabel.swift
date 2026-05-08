import SwiftUI

/// `.gf-row-label` — the small uppercase label that opens every Settings row.
/// Width is fixed so labels and controls line up vertically across the page.
struct SettingsRowLabel: View {
    let text: String

    /// Shared label width so adjacent rows align even when their contents
    /// have different intrinsic widths.
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
