import SwiftUI

/// Strip pinned to the bottom of the inspector while the diff pane is
/// collapsed. Click anywhere to show the pane again. (The inspector itself
/// comes back with the toolbar button or ⌃⌘I.)
struct CollapsedPaneStrip: View {
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s8) {
                SymbolGlyph("plus.forwardslash.minus", size: 12)
                    .foregroundStyle(theme.colors.textSecondary)
                Text("Show diff pane")
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textSecondary)
                Spacer(minLength: 0)
                SymbolGlyph("arrow.up", size: 11)
                    .foregroundStyle(theme.colors.textTertiary)
            }
            .padding(.horizontal, Spacing.s12)
            .frame(height: 30)
            .frame(maxWidth: .infinity)
            .background {
                theme.colors.bgElevated
                if hovering { theme.colors.fillHover }
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(theme.colors.strokeControl)
                    .frame(height: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Show the diff pane")
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    CollapsedPaneStrip(action: {})
        .frame(width: 720)
        .appTheme(theme)
}
