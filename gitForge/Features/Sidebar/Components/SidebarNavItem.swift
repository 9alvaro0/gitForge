import SwiftUI

/// Workspace navigation row with icon, label and optional count
/// (redesign spec §5, list row).
struct SidebarNavItem: View {
    let section: WorkspaceSection
    let badge: Int?
    let isActive: Bool
    let onSelect: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.s8) {
                GFIcon(kind: section.icon, size: 16, stroke: isActive ? theme.colors.accent : theme.colors.textTertiary)
                Text(section.label)
                    .textRole(.body, weight: isActive ? .semibold : .regular)
                    .foregroundStyle(isActive ? theme.colors.accent : theme.colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .textRole(.caption)
                        .foregroundStyle(isActive ? theme.colors.accent : theme.colors.textTertiary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, Spacing.s8)
            .frame(height: theme.density.metrics.rowSidebar)
            .background(RoundedRectangle(cornerRadius: Radius.row).fill(rowBackground))
            .contentShape(.rect(cornerRadius: Radius.row))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    /// Redesign spec §5 list row: accent-soft when active, hover fill otherwise.
    private var rowBackground: Color {
        if isActive { return theme.colors.accentSoft }
        return hovering ? theme.colors.fillHover : .clear
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var active: WorkspaceSection = .history
    VStack(spacing: 1) {
        ForEach(WorkspaceSection.workspaceItems) { s in
            SidebarNavItem(section: s,
                           badge: s == .changes ? 3 : (s == .pulls ? 2 : nil),
                           isActive: s == active,
                           onSelect: { active = s })
        }
    }
    .frame(width: 240)
    .padding(.vertical, Spacing.s6)
    .background(theme.colors.bgWindow)
    .appTheme(theme)
}
