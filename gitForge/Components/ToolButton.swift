import SwiftUI

/// `.gf-tbtn` — toolbar pill button with optional icon, label and badge count.
struct ToolButton<Icon: View>: View {
    var icon: Icon? = nil
    var label: String? = nil
    var badge: Int? = nil
    var primary: Bool = false
    var disabled: Bool = false
    var action: () -> Void = {}

    @Environment(\.appTheme) private var theme
    @State private var hovering = false

    init(label: String? = nil,
         badge: Int? = nil,
         primary: Bool = false,
         disabled: Bool = false,
         action: @escaping () -> Void = {},
         @ViewBuilder icon: () -> Icon) {
        self.icon = icon()
        self.label = label
        self.badge = badge
        self.primary = primary
        self.disabled = disabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                icon
                if let label {
                    Text(label).font(AppFont.sans(12))
                }
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(AppFont.mono(10, family: theme.monoFont))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(badgeBg))
                        .foregroundStyle(badgeFg)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .foregroundStyle(fg)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(bg))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .onHover { hovering = $0 }
    }

    private var bg: Color {
        if primary { return theme.palette.accent }
        return hovering ? theme.palette.bg4 : theme.palette.bg3
    }
    private var fg: Color {
        if primary { return theme.palette.accentFg }
        return hovering ? theme.palette.fg1 : theme.palette.fg2
    }
    private var border: Color {
        if primary { return theme.palette.accent }
        return hovering ? theme.palette.lineStrong : theme.palette.line
    }
    private var badgeBg: Color {
        primary ? Color.white.opacity(0.22) : theme.palette.bg2
    }
    private var badgeFg: Color {
        primary ? .white : theme.palette.fg1
    }
}

/// Convenience initializer for `ToolButton` driven by a `GFIconKind`.
extension ToolButton where Icon == GFIcon {
    init(_ kind: GFIconKind,
         label: String? = nil,
         badge: Int? = nil,
         primary: Bool = false,
         disabled: Bool = false,
         action: @escaping () -> Void = {}) {
        self.init(label: label, badge: badge, primary: primary, disabled: disabled, action: action) {
            GFIcon(kind: kind, size: 14)
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(alignment: .leading, spacing: 8) {
        HStack {
            ToolButton(.fetch, label: "Fetch") { }
            ToolButton(.pull,  label: "Pull",  badge: 1) { }
            ToolButton(.push,  label: "Push",  badge: 7, primary: true) { }
        }
        HStack {
            ToolButton(.plus, label: "New PR", primary: true) { }
            ToolButton(.x, label: "Disabled", disabled: true) { }
            ToolButton(.stash, label: "Stash") { }
        }
    }
    .padding(20)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
