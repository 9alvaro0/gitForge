import SwiftUI

/// "Uncommitted changes" row pinned to the top of the log when the working
/// tree is dirty. Mirrors the column layout of a real `CommitRow` so the
/// graph gutter and column boundaries line up, and behaves like a row — a
/// single tap selects it (host wires the click into the working-copy file
/// list + diff pane), and a double tap can be routed elsewhere if needed.
/// Under its square starts the connector down to HEAD's commit (graph v3 spec §5.5).
struct UncommittedRow: View {
    let rowHeight: CGFloat
    let layout: HistoryTableLayout
    let isSelected: Bool
    let onSelect: () -> Void
    var onDoubleClick: (() -> Void)? = nil
    /// The connector's half this row draws under its square (`HistoryStore.uncommittedStep`);
    /// nil draws the square alone (no HEAD yet, or no rows).
    var connector: GraphStep? = nil
    /// The table's graph look, so the connector matches the rows below it.
    var graphStyle = GraphStyle()
    /// Column count of the whole graph (`HistoryStore.graphMaxLanes`): the connector's
    /// canvas is as wide as a graph row's.
    var maxLanes = 1

    /// Side of the dashed square, centred on lane 0.
    static let squareSide: CGFloat = 9

    @Environment(\.appTheme) private var theme

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                if let connector {
                    UncommittedConnectorView(step: connector, maxLanes: maxLanes, style: graphStyle,
                                             rowSpacing: HistoryTableLayout.rowSpacing,
                                             squareSide: Self.squareSide)
                }
                RoundedRectangle(cornerRadius: GraphMetrics.squareMarkRadius)
                    .strokeBorder(theme.colors.mod, style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2]))
                    .frame(width: Self.squareSide, height: Self.squareSide)
                    .padding(.leading, theme.density.metrics.graph.firstLaneX - Self.squareSide / 2)
            }
            .frame(width: layout.graph, alignment: .leading)
            Color.clear.frame(width: HistoryTableLayout.gap)
            Text("Uncommitted changes")
                .textRole(.body)
                .italic()
                .foregroundStyle(theme.colors.mod)
                .frame(width: layout.description, alignment: .leading)
            Color.clear.frame(width: HistoryTableLayout.gap + (layout.showsAuthor ? layout.author + HistoryTableLayout.gap : 0))
            Text("now")
                .textRole(.callout)
                .foregroundStyle(theme.colors.textTertiary)
                .frame(width: layout.date, alignment: .leading)
            Color.clear.frame(width: HistoryTableLayout.gap)
            Text(verbatim: "–")
                .textRole(.monoSmall)
                .foregroundStyle(theme.colors.textTertiary)
                .frame(width: layout.commit, alignment: .trailing)
            Spacer(minLength: 0)
        }
        .padding(.leading, HistoryTableLayout.leadingPadding)
        .padding(.trailing, HistoryTableLayout.trailingPadding)
        .frame(height: rowHeight)
        .background(RoundedRectangle(cornerRadius: Radius.row).fill(rowBackground))
        .padding(.horizontal, HistoryTableLayout.rowInset)
        .onHover { hovering = $0 }
        .contentShape(.rect)
        .onTapGesture(count: 2) { onDoubleClick?() }
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Uncommitted changes")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { onSelect() }
    }

    private var rowBackground: Color {
        if isSelected { return theme.colors.accentSoft }
        return hovering ? theme.colors.fillHover : theme.colors.modSoft.opacity(0.5)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var columns = ResizableTableModel.historyColumns(id: "history.uncommitted.preview")
    let tableLayout = HistoryTableLayout(viewport: 1100, graph: 80, author: 112, date: 92, commit: 64)
    // Resolved from the theme as `CommitGraphTable` does.
    let style = GraphStyle(metrics: theme.density.metrics.graph, accent: theme.accentSwatch,
                           accentColor: theme.colors.accent, dark: theme.effectiveMode == .dark,
                           nodeFill: theme.colors.bgContent)
    // HEAD's commit right below: the connector arrives from the row above it.
    let headRow = GraphRow(node: GraphNode(column: 0, kind: .commit, color: .head, isGhost: false),
                           stepsAbove: [.uncommitted], stepsBelow: [], width: 1)
    VStack(spacing: Spacing.s16) {
        // The square alone (no HEAD yet), unselected and selected.
        VStack(spacing: 0) {
            UncommittedRow(rowHeight: 28, layout: tableLayout, isSelected: false, onSelect: {})
            UncommittedRow(rowHeight: 28, layout: tableLayout, isSelected: true, onSelect: {})
        }
        // The connector under the square, over HEAD's row, spaced like the History table.
        VStack(spacing: HistoryTableLayout.rowSpacing) {
            UncommittedRow(rowHeight: 28, layout: tableLayout, isSelected: false, onSelect: {},
                           connector: .uncommitted, graphStyle: style, maxLanes: 1)
            CommitRow(
                commit: Commit.previewSamples[0],
                layout: headRow,
                maxLanes: 1,
                rowHeight: 28,
                tableLayout: tableLayout,
                chips: .empty,
                currentBranch: "main",
                isSelected: false,
                graphStyle: style,
                isHeadCommit: true,
                dimmed: false,
                onSelect: {}, onDoubleClick: {}, onBranchDrop: nil
            )
        }
    }
    .frame(width: 1100)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
