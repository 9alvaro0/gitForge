import SwiftUI

/// Card wrapper for a Settings section: uppercase header on top of a bordered
/// container that hosts the section's rows. Rows are separated by
/// `SettingsDivider`s that the caller intersperses between children — this
/// keeps the API transparent without needing variadic-view tricks.
struct SettingsSection<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.none) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(title.uppercased())
                    .font(.system(size: FontSize.footnote, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(theme.palette.fg3)
                if let subtitle {
                    Text(subtitle)
                        .font(AppFont.sans(11))
                        .foregroundStyle(theme.palette.fg3)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.top, DesignTokens.Spacing.lg)
            .padding(.bottom, DesignTokens.Spacing.md)

            SettingsDivider()

            VStack(spacing: DesignTokens.Spacing.none) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
    }
}

/// Hairline divider used between rows inside a `SettingsSection`. Painted
/// with the theme's `line` colour so it tracks light/dark variants.
struct SettingsDivider: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.palette.line)
            .frame(height: DesignTokens.Stroke.regular)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    SettingsSection(title: "Identity", subtitle: "Identity recorded on every commit.") {
        Text("Row 1")
            .padding(DesignTokens.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        SettingsDivider()
        Text("Row 2")
            .padding(DesignTokens.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(width: 520)
    .padding(DesignTokens.Spacing.huge)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
