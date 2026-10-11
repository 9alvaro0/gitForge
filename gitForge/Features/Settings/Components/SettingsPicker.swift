import SwiftUI

struct SettingsPicker<Items: View>: View {
    let current: String
    @ViewBuilder var items: () -> Items

    @Environment(\.appTheme) private var theme

    var body: some View {
        Menu {
            items()
        } label: {
            HStack(spacing: Spacing.s6) {
                Text(current)
                    .textRole(.body)
                    .foregroundStyle(theme.colors.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.colors.textTertiary)
            }
            .padding(.horizontal, Spacing.s8)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: Radius.control).fill(theme.colors.bgContent))
            .overlay(RoundedRectangle(cornerRadius: Radius.control).stroke(theme.colors.strokeControl, lineWidth: 1))
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
    .padding(Spacing.s20)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
