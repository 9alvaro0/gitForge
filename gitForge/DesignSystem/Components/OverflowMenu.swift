import SwiftUI

/// `…` overflow menu used in row actions. Reliable on macOS: a tappable
/// 26×26 hit area, our own glyph, the native chevron hidden, and dropdown
/// items provided by the caller.
struct OverflowMenu<Content: View>: View {
    var accessibilityLabel: String = String(localized: "More options")
    @ViewBuilder var content: () -> Content

    @Environment(\.appTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Menu {
            content()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.controlSmall)
                    .fill(hovering ? theme.colors.fillHover : .clear)
                SymbolGlyph("ellipsis", size: 14, framed: false)
                    .foregroundStyle(hovering ? theme.colors.textPrimary : theme.colors.textTertiary)
            }
            .frame(width: 26, height: 26)
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(accessibilityLabel)
        .onHover { hovering = $0 }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    HStack(spacing: Spacing.s8) {
        OverflowMenu {
            Button("Checkout") {}
            Button("Rename…") {}
            Divider()
            Button("Delete…", role: .destructive) {}
        }
        Text("← click").foregroundStyle(theme.colors.textTertiary)
    }
    .padding(Spacing.s20)
    .background(theme.colors.bgElevated)
    .appTheme(theme)
}
