import SwiftUI

struct GFCheckboxStyle: ToggleStyle {
    @Environment(\.appTheme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                    .fill(configuration.isOn ? theme.palette.accent : theme.palette.bg2)
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                    .stroke(configuration.isOn ? theme.palette.accent : theme.palette.lineStrong,
                            lineWidth: DesignTokens.Stroke.regular)
                if configuration.isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: FontSize.caption, weight: .bold))
                        .foregroundStyle(theme.palette.accentFg)
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
