import SwiftUI

/// Mimics the HTML `<kbd>` chip used across the design (search trigger, command palette).
struct Kbd: View {
    let text: String
    @Environment(\.appTheme) private var theme

    var body: some View {
        Text(text)
            .textRole(.monoSmall)
            .foregroundStyle(theme.colors.textTertiary)
            .padding(.horizontal, Spacing.s4)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: Radius.badge).strokeBorder(theme.colors.strokeControl, lineWidth: 1))
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    HStack {
        Kbd(text: "⌘K")
        Kbd(text: "⌥⌘P")
        Kbd(text: "esc")
        Kbd(text: "↵")
    }
    .padding(DesignTokens.Spacing.huge)
    .background(theme.palette.bg2)
    .appTheme(theme)
}

