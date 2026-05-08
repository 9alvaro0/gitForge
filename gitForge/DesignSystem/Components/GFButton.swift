import SwiftUI

/// `.gf-btn` / `.gf-btn-primary` / `.gf-btn-sm` — generic button.
struct GFButton: View {
    enum Style { case secondary, primary }
    enum Size  { case regular, small }

    let title: String
    var style: Style = .secondary
    var size: Size = .regular
    var disabled: Bool = false
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppFont.sans(size == .small ? 11 : 12))
                .padding(.horizontal, size == .small ? 8 : 12)
                .frame(height: size == .small ? 22 : 28)
                .foregroundStyle(fg)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(bg))
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(border, lineWidth: DesignTokens.Stroke.regular))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? DesignTokens.Opacity.disabled : 1)
        .onHover { hovering = $0 }
    }

    private var bg: Color {
        switch style {
        case .primary:  return theme.palette.accent
        case .secondary: return hovering ? theme.palette.bg4 : theme.palette.bg3
        }
    }
    private var fg: Color {
        style == .primary ? theme.palette.accentFg : theme.palette.fg1
    }
    private var border: Color {
        style == .primary ? theme.palette.accent : theme.palette.lineStrong
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(spacing: DesignTokens.Spacing.md) {
        HStack {
            GFButton(title: "Secondary") { }
            GFButton(title: "Primary", style: .primary) { }
            GFButton(title: "Disabled", disabled: true) { }
        }
        HStack {
            GFButton(title: "Small", size: .small) { }
            GFButton(title: "Small primary", style: .primary, size: .small) { }
        }
    }
    .padding(DesignTokens.Spacing.huge)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
