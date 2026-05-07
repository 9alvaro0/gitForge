import SwiftUI

/// `.gf-search-trigger` — opens the command palette when tapped.
struct SidebarSearchTrigger: View {
    let action: () -> Void
    @Environment(\.appTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                GFIcon(kind: .search, size: 14, stroke: theme.palette.fg3)
                Text("Search")
                    .font(AppFont.sans(12))
                    .foregroundStyle(theme.palette.fg3)
                Spacer()
                Kbd(text: "⌘K")
            }
            .padding(.horizontal, 10)
            .frame(height: DesignTokens.Sidebar.searchHeight)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(hovering ? theme.palette.bg3 : theme.palette.bg2))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.lineStrong, lineWidth: 1))
            .contentShape(.rect(cornerRadius: DesignTokens.Radius.md))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    SidebarSearchTrigger(action: {})
        .frame(width: 240)
        .padding(20)
        .background(theme.palette.bg1)
        .appTheme(theme)
}
