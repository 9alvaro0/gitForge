import SwiftUI

/// 26×26 borderless icon-only button (redesign spec §5).
struct IconButton<Content: View>: View {
    let action: () -> Void
    let accessibilityLabel: String
    @ViewBuilder var content: () -> Content

    @Environment(\.appTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content()
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: Radius.control).fill(hovering ? theme.colors.fillHover : .clear))
                .foregroundStyle(hovering ? theme.colors.textPrimary : theme.colors.textTertiary)
                .contentShape(.rect(cornerRadius: Radius.control))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .onHover { hovering = $0 }
    }
}

/// SF Symbol glyph sized like the old icon box (symbols fill more of their
/// point size than the previous line glyphs, hence the 0.8 scale).
struct IconButtonGlyph: View {
    let symbol: String
    let size: CGFloat

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.8, weight: .medium))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

extension IconButton where Content == IconButtonGlyph {
    /// `symbol` is an SF Symbol name.
    init(symbol: String, size: CGFloat = 14, accessibilityLabel: String, action: @escaping () -> Void) {
        self.action = action
        self.accessibilityLabel = accessibilityLabel
        self.content = { IconButtonGlyph(symbol: symbol, size: size) }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    HStack(spacing: Spacing.s6) {
        IconButton(symbol: "ellipsis", accessibilityLabel: "More") {}
        IconButton(symbol: "doc.on.doc", accessibilityLabel: "Copy") {}
        IconButton(symbol: "magnifyingglass", accessibilityLabel: "Search") {}
        IconButton(symbol: "arrow.up.right.square", accessibilityLabel: "Open externally") {}
    }
    .padding(Spacing.s20)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
