import SwiftUI

/// Collapsible folder header inside `BranchListSection`. Single-line button
/// that toggles the folder via `onToggle`; the row body shows the chevron,
/// folder icon, name and total leaf count under it.
struct BranchFolderRow: View {
    let name: String
    let depth: Int
    let leafCount: Int
    let isCollapsed: Bool
    let onToggle: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Spacer().frame(width: BranchRowMetrics.indent(depth: depth))
                GFIcon(kind: isCollapsed ? .chevR : .chevD,
                       size: 10, stroke: theme.palette.fg3)
                GFIcon(kind: .folder, size: 12, stroke: theme.palette.fg2)
                Text(name)
                    .font(AppFont.sans(12, weight: .medium))
                    .foregroundStyle(theme.palette.fg1)
                Text("\(leafCount)")
                    .font(AppFont.mono(10.5, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg3)
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.palette.line).frame(height: DesignTokens.Stroke.regular)
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(spacing: 0) {
        BranchFolderRow(name: "feature", depth: 0, leafCount: 12, isCollapsed: false, onToggle: {})
        BranchFolderRow(name: "release", depth: 0, leafCount: 3, isCollapsed: true, onToggle: {})
        BranchFolderRow(name: "ios", depth: 1, leafCount: 5, isCollapsed: false, onToggle: {})
    }
    .frame(width: 720)
    .background(theme.palette.bg3)
    .appTheme(theme)
}
