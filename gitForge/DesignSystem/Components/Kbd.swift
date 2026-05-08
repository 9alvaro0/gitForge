import SwiftUI

/// Mimics the HTML `<kbd>` chip used across the design (search trigger, command palette).
struct Kbd: View {
    let text: String
    @Environment(\.appTheme) private var theme

    var body: some View {
        Text(text)
            .font(AppFont.mono(10, family: theme.monoFont))
            .foregroundStyle(theme.palette.fg3)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.hairline)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                    .fill(theme.palette.bg3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                    .stroke(theme.palette.lineStrong, lineWidth: DesignTokens.Stroke.regular)
            )
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

