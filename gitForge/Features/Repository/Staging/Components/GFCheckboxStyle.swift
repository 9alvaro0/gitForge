import SwiftUI

struct GFCheckboxStyle: ToggleStyle {
    @Environment(\.appTheme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.badge)
                    .fill(configuration.isOn ? theme.colors.accentFill : theme.colors.bgContent)
                RoundedRectangle(cornerRadius: Radius.badge)
                    .strokeBorder(configuration.isOn ? theme.colors.accentFill : theme.colors.strokeControl,
                                  lineWidth: 1)
                if configuration.isOn {
                    GFIcon(kind: .check, size: DesignTokens.IconSize.xs, stroke: theme.colors.accentOnFill)
                }
            }
            .frame(width: DesignTokens.IconSize.md, height: DesignTokens.IconSize.md)
            .contentShape(.rect(cornerRadius: DesignTokens.Radius.xs))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var on = true
    @Previewable @State var off = false
    HStack(spacing: 16) {
        Toggle("", isOn: $on).toggleStyle(GFCheckboxStyle())
        Toggle("", isOn: $off).toggleStyle(GFCheckboxStyle())
    }
    .padding()
    .appTheme(theme)
}
