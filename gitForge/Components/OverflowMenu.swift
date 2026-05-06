import SwiftUI

/// `…` overflow menu used in row actions. Reliable on macOS: a tappable
/// 26×26 hit area, our own glyph, the native chevron hidden, and dropdown
/// items provided by the caller.
struct OverflowMenu<Content: View>: View {
    @ViewBuilder var content: () -> Content

    @Environment(\.appTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Menu {
            content()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(hovering ? theme.palette.bg3 : .clear)
                GFIcon(kind: .more, size: 14, stroke: hovering ? theme.palette.fg1 : theme.palette.fg3)
            }
            .frame(width: 26, height: 26)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    HStack(spacing: 8) {
        OverflowMenu {
            Button("Checkout") {}
            Button("Rename…") {}
            Divider()
            Button("Delete…", role: .destructive) {}
        }
        Text("← click").foregroundStyle(theme.palette.fg3)
    }
    .padding(20)
    .background(theme.palette.bg1)
    .appTheme(theme)
}
