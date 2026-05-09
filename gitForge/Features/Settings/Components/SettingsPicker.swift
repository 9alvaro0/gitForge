import SwiftUI

struct SettingsPicker<Items: View>: View {
    let current: String
    @ViewBuilder var items: () -> Items

    @Environment(\.appTheme) private var theme

    var body: some View {
        Menu {
            items()
        } label: {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Text(current)
                    .font(AppFont.sans(12))
                    .foregroundStyle(theme.palette.fg1)
                Spacer(minLength: 0)
                GFIcon(kind: .chevD, size: 10, stroke: theme.palette.fg3)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .frame(height: DesignTokens.IconSize.xxl)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).fill(theme.palette.bg2))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).stroke(theme.palette.lineStrong, lineWidth: DesignTokens.Stroke.regular))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var current = "Rebase"
    SettingsPicker(current: current) {
        Button("Default (git config)") { current = "Default" }
        Divider()
        Button("Rebase") { current = "Rebase" }
        Button("Merge") { current = "Merge" }
        Button("Fast-forward only") { current = "Fast-forward only" }
    }
    .frame(width: 240)
    .padding(DesignTokens.Spacing.huge)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
