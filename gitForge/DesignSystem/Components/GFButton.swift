import SwiftUI

/// In-content button (redesign spec §5). Toolbar actions use native toolbar
/// buttons instead, so the window's Liquid Glass is their only chrome.
struct GFButton: View {
    enum Style { case secondary, primary, destructive }
    enum Size  { case regular, small }

    let title: String
    var systemImage: String? = nil
    var style: Style = .secondary
    var size: Size = .regular
    var disabled: Bool = false
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: size == .small ? 10 : 12, weight: .semibold))
                }
                Text(title)
                    .textRole(size == .small ? .caption : .callout, weight: .semibold)
            }
            .lineLimit(1)
            .padding(.horizontal, size == .small ? 9 : 14)
            .frame(height: height)
            .foregroundStyle(foreground)
            .background(shape.fill(background))
            .overlay(shape.fill(hoverOverlay))
            .overlay(shape.strokeBorder(border, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size == .small ? Radius.controlSmall : Radius.control)
    }

    private var height: CGFloat {
        let metrics = theme.density.metrics
        return size == .small ? metrics.buttonSmall : metrics.buttonRegular
    }

    private var background: Color {
        if disabled { return theme.colors.fillControl }
        switch style {
        case .primary:     return theme.colors.accentFill
        case .secondary:   return theme.colors.fillControl
        case .destructive: return theme.colors.delSoft
        }
    }

    private var foreground: Color {
        if disabled { return theme.colors.textQuaternary }
        switch style {
        case .primary:     return theme.colors.accentOnFill
        case .secondary:   return theme.colors.textPrimary
        case .destructive: return theme.colors.del
        }
    }

    private var border: Color {
        style == .secondary && !disabled ? theme.colors.strokeControl : .clear
    }

    /// Hover lightens in dark mode and darkens in light mode.
    private var hoverOverlay: Color {
        guard hovering, !disabled else { return .clear }
        return theme.effectiveMode == .dark ? .white.opacity(0.08) : .black.opacity(0.06)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(alignment: .leading, spacing: Spacing.s8) {
        HStack {
            GFButton(title: "Secondary") { }
            GFButton(title: "Primary", style: .primary) { }
            GFButton(title: "Discard…", style: .destructive) { }
            GFButton(title: "Disabled", disabled: true) { }
        }
        HStack {
            GFButton(title: "Open in browser", systemImage: "arrow.up.right.square") { }
            GFButton(title: "Small", size: .small) { }
            GFButton(title: "Small primary", style: .primary, size: .small) { }
        }
    }
    .padding(Spacing.s20)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
