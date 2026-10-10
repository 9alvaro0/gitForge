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

extension IconButton where Content == GFIcon {
    init(_ kind: GFIconKind, size: CGFloat = 14, accessibilityLabel: String, action: @escaping () -> Void) {
        self.action = action
        self.accessibilityLabel = accessibilityLabel
        self.content = { GFIcon(kind: kind, size: size) }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    HStack(spacing: DesignTokens.Spacing.sm) {
        IconButton(.more, accessibilityLabel: "More") {}
        IconButton(.copy, accessibilityLabel: "Copy") {}
        IconButton(.search, accessibilityLabel: "Search") {}
        IconButton(.ext, accessibilityLabel: "Open externally") {}
    }
    .padding(DesignTokens.Spacing.huge)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
