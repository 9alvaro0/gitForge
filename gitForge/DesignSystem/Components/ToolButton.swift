import SwiftUI

/// `.gf-tbtn` — toolbar pill button with optional icon, label and badge count.
struct ToolButton<Icon: View>: View {
    var icon: Icon? = nil
    var label: String? = nil
    var badge: Int? = nil
    var primary: Bool = false
    var disabled: Bool = false
    var loading: Bool = false
    var action: () -> Void = {}

    @Environment(\.appTheme) private var theme
    @State private var hovering = false

    init(label: String? = nil,
         badge: Int? = nil,
         primary: Bool = false,
         disabled: Bool = false,
         loading: Bool = false,
         action: @escaping () -> Void = {},
         @ViewBuilder icon: () -> Icon) {
        self.icon = icon()
        self.label = label
        self.badge = badge
        self.primary = primary
        self.disabled = disabled
        self.loading = loading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if loading {
                    SpinnerGlyph(color: fg)
                } else {
                    icon
                }
                if let label {
                    Text(label).font(AppFont.sans(12))
                }
                if let badge, badge > 0, !loading {
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
        .disabled(disabled || loading)
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
         loading: Bool = false,
         action: @escaping () -> Void = {}) {
        self.init(label: label, badge: badge, primary: primary, disabled: disabled, loading: loading, action: action) {
            GFIcon(kind: kind, size: 14)
        }
    }
}

/// 14×14 spinning arc that matches the toolbar icon footprint. Plays nicely
/// with primary/secondary backgrounds because it inherits the foreground tint.
struct SpinnerGlyph: View {
    var color: Color = .primary
    var size: CGFloat = 14
    var lineWidth: CGFloat = 1.6

    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0.12, to: 0.92)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
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
            ToolButton(.fetch, label: "Fetching", loading: true) { }
            ToolButton(.pull,  label: "Pulling",  badge: 3, loading: true) { }
            ToolButton(.push,  label: "Pushing",  badge: 7, primary: true, loading: true) { }
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
