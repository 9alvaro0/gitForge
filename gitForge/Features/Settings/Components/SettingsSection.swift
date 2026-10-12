import SwiftUI

/// Bordered card with a header that hosts a section's rows.
/// Callers intersperse `SettingsDivider` between children manually — that
/// keeps the API a plain `@ViewBuilder` instead of needing variadic-view
/// tricks to auto-insert separators.
struct SettingsSection<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text(title)
                    .textRole(.headline)
                    .foregroundStyle(theme.colors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .textRole(.callout)
                        .foregroundStyle(theme.colors.textTertiary)
                }
            }
            .padding(.horizontal, Spacing.s12)
            .padding(.top, Spacing.s12)
            .padding(.bottom, Spacing.s8)

            SettingsDivider()

            VStack(spacing: 0) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card).fill(theme.colors.bgElevated))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(theme.colors.separator, lineWidth: 1))
    }
}

struct SettingsDivider: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.colors.separator)
            .frame(height: 1)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    SettingsSection(title: "Identity", subtitle: "Identity recorded on every commit.") {
        Text("Row 1")
            .padding(Spacing.s12)
            .frame(maxWidth: .infinity, alignment: .leading)
        SettingsDivider()
        Text("Row 2")
            .padding(Spacing.s12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(width: 520)
    .padding(Spacing.s20)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
