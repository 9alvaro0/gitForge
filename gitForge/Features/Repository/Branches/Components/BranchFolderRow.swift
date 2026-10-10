import SwiftUI

/// Collapsible folder (`feature/`, `release/`…) inside the Branches & Tags
/// table: chevron, folder glyph, name and how many refs it holds.
struct BranchFolderRow: View {
    let name: String
    let depth: Int
    let leafCount: Int
    let isCollapsed: Bool
    let onToggle: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: Spacing.s6) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 16)
                Image(systemName: "folder")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.colors.textTertiary)
                Text(name)
                    .textRole(.body, weight: .medium)
                    .foregroundStyle(theme.colors.textPrimary)
                Text("\(leafCount)")
                    .textRole(.caption)
                    .foregroundStyle(theme.colors.textTertiary)
                Spacer(minLength: 0)
            }
            .padding(.leading, Spacing.s12 + BranchRow.indent(depth: depth))
            .padding(.trailing, Spacing.s12)
            .frame(height: theme.density.metrics.rowBranch)
            .background(RoundedRectangle(cornerRadius: Radius.row).fill(hovering ? theme.colors.fillHover : .clear))
            .contentShape(.rect(cornerRadius: Radius.row))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(name) folder, \(leafCount) \(leafCount == 1 ? "item" : "items")")
        .accessibilityValue(isCollapsed ? "collapsed" : "expanded")
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
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
