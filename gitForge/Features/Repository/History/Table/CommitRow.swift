import SwiftUI

struct CommitRow: View {
    let commit: Commit
    let layout: GraphRowLayout
    let maxLanes: Int
    let rowHeight: CGFloat
    let gutterWidth: CGFloat
    let refs: [GitRef]
    let currentBranch: String?
    let isSelected: Bool
    let dimmed: Bool
    let columns: ResizableTableModel
    let onSelect: () -> Void
    let onDoubleClick: () -> Void
    let onBranchDrop: ((DraggedBranch, BranchDropContext) -> Void)?

    @Environment(\.appTheme) private var theme
    @State private var rowDropTargeted = false

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.none) {
            graphGutter
                .frame(width: gutterWidth, alignment: .leading)
            Color.clear.frame(width: DesignTokens.Spacing.md)
            CommitRowChips(
                commitSha: commit.sha,
                refs: refs,
                currentBranch: currentBranch,
                onBranchDrop: onBranchDrop
            )
            .frame(width: columns.width("branchTag"), alignment: .leading)
            Color.clear.frame(width: DesignTokens.Spacing.md)
            Text(commit.subject)
                .font(AppFont.sans(12.5))
                .foregroundStyle(theme.palette.fg1)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: columns.width("message"), alignment: .leading)
            Color.clear.frame(width: DesignTokens.Spacing.md)
            HStack(spacing: DesignTokens.Spacing.sm) {
                Avatar(name: commit.authorName, size: 16, colorSeed: commit.authorEmail)
                Text(commit.authorName)
                    .font(AppFont.sans(12))
                    .foregroundStyle(theme.palette.fg2)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: columns.width("author"), alignment: .leading)
            Color.clear.frame(width: DesignTokens.Spacing.md)
            Text(commit.shortSha)
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
                .frame(width: columns.width("sha"), alignment: .leading)
            Color.clear.frame(width: DesignTokens.Spacing.md)
            Text(theme.dateDisplayMode.format(commit.authorDate))
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
                .frame(width: columns.width("when"), alignment: .trailing)
            Color.clear.frame(width: DesignTokens.Spacing.md)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignTokens.Spacing.xxxxl)
        .frame(height: rowHeight)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if isSelected { Rectangle().fill(theme.palette.accent).frame(width: 2) }
        }
        .opacity(dimmed ? 0.35 : 1)
        .contentShape(.rect)
        .onTapGesture(count: 2, perform: onDoubleClick)
        .onTapGesture(perform: onSelect)
        .modifier(RowDropModifier(
            enabled: onBranchDrop != nil,
            targetSha: commit.sha,
            isTargeted: $rowDropTargeted,
            onDrop: { dropped in
                onBranchDrop?(dropped, .onCommit(targetSha: commit.sha))
            }
        ))
    }

    /// Re-uses the existing `GraphColumnView` so lane drawing matches the
    /// rest of the app.
    private var graphGutter: some View {
        HStack(spacing: DesignTokens.Spacing.none) {
            Spacer().frame(width: DesignTokens.IconSize.xl)
            GraphColumnView(row: layout, maxLanes: max(maxLanes, 1))
        }
    }

    private var rowBackground: Color {
        if rowDropTargeted { return theme.palette.accent.opacity(DesignTokens.Opacity.subtle) }
        if isSelected { return theme.palette.accentSoft }
        return .clear
    }
}
