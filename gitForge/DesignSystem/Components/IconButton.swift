import SwiftUI

/// `.gf-icon-btn` — 26×26 borderless icon-only button.
struct IconButton<Content: View>: View {
    let action: () -> Void
    @ViewBuilder var content: () -> Content

    @Environment(\.appTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content()
                .frame(width: DesignTokens.IconSize.huge, height: DesignTokens.IconSize.huge)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).fill(hovering ? theme.palette.bg3 : .clear))
                .foregroundStyle(hovering ? theme.palette.fg1 : theme.palette.fg3)
                .contentShape(.rect(cornerRadius: DesignTokens.Radius.sm))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

extension IconButton where Content == GFIcon {
    init(_ kind: GFIconKind, size: CGFloat = 14, action: @escaping () -> Void) {
        self.action = action
        self.content = { GFIcon(kind: kind, size: size) }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    HStack(spacing: DesignTokens.Spacing.sm) {
        IconButton(.more, action: {})
        IconButton(.copy, action: {})
        IconButton(.search, action: {})
        IconButton(.ext, action: {})
    }
    .padding(DesignTokens.Spacing.huge)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
