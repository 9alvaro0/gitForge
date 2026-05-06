import SwiftUI

/// `.gf-nav-item` — single workspace nav row with icon, label, optional badge.
struct SidebarNavItem: View {
    let section: WorkspaceSection
    let badge: Int?
    let isActive: Bool
    let onSelect: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 9) {
                GFIcon(kind: section.icon, size: 14, stroke: foreground.opacity(isActive ? 1 : 0.85))
                Text(section.label)
                    .font(AppFont.sans(12))
                    .foregroundStyle(foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(AppFont.mono(10, family: theme.monoFont))
                        .foregroundStyle(badgeForeground)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(badgeBackground))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: DesignTokens.Sidebar.navRow)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(rowBackground))
            .overlay(alignment: .leading) {
                if isActive {
                    Rectangle()
                        .fill(theme.palette.accent)
                        .frame(width: 2, height: 16)
                        .cornerRadius(1)
                        .offset(x: -7)
                }
            }
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var foreground: Color {
        if isActive { return theme.palette.accent }
        return hovering ? theme.palette.fg1 : theme.palette.fg2
    }
    private var rowBackground: Color {
        if isActive { return theme.palette.accentSoft }
        return hovering ? theme.palette.bg3 : .clear
    }
    private var badgeBackground: Color {
        isActive ? theme.palette.accent : theme.palette.bg4
    }
    private var badgeForeground: Color {
        isActive ? theme.palette.accentFg : theme.palette.fg2
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var active: WorkspaceSection = .history
    VStack(spacing: 1) {
        ForEach(WorkspaceSection.allCases) { s in
            SidebarNavItem(section: s,
                           badge: s == .changes ? 3 : (s == .pulls ? 2 : nil),
                           isActive: s == active,
                           onSelect: { active = s })
        }
    }
    .frame(width: 256)
    .padding(.vertical, 6)
    .background(theme.palette.bg1)
    .appTheme(theme)
}
