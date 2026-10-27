import SwiftUI

/// Header + data table for the History view. Owns its own dual-axis ScrollView
/// so columns line up between header and rows even when the graph gutter is
/// wide enough to push the row past the viewport — horizontal scroll engages
/// automatically. The header is pinned via a `LazyVStack` Section so it stays
/// at the top during vertical scroll and slides with content during horizontal
/// scroll (so the labels never desync from the columns below).
///
/// Drag handles (`CommitTableHeader`) sit on the edge that moves when their
/// column resizes, so every divider the eye lands on follows the pointer.
struct CommitGraphTable: View {
    let commits: [Commit]
    /// `HistoryStore.logRevision` of `commits`: a log published again while
    /// its end is on screen pages in more again (`CommitRowList`).
    var logRevision: UInt64 = 0
    let layouts: [GraphRow]
    /// Column count of the whole graph layout (`HistoryStore.graphMaxLanes`,
    /// taken once per layout pass; it includes columns reserved for HEAD and
    /// the trunks, so it can exceed the widest row). Recomputing it here walked
    /// every layout, and did so for each row SwiftUI built — O(visible rows ×
    /// commits) on every re-render of History.
    let maxLanes: Int
    /// The refs drawn as chips (`HistoryStore.refChips`), published with the layouts.
    let refChips: HistoryRefChips
    let currentBranch: String?
    /// Commit HEAD points at (detached or not); marks HEAD in the graph.
    var headSha: String? = nil
    let selectedSha: Commit.ID?
    /// Pins the "Uncommitted changes" row on top (`HistoryStore.showsUncommittedRow`):
    /// it comes with the graph laid out for the dirty tree, so it and its connector
    /// appear and go together.
    let showsUncommittedRow: Bool
    /// The connector's half the "Uncommitted changes" row draws under its square
    /// (`HistoryStore.uncommittedStep`); nil when there is no connector.
    var uncommittedStep: GraphStep? = nil
    /// `true` when the pinned "Uncommitted changes" row is the active selection
    /// in the host. Lets the row render the same accent treatment as a selected
    /// commit row.
    var uncommittedSelected: Bool = false
    let columns: ResizableTableModel
    /// `nil` when search is inactive — every row renders at full opacity. When
    /// non-nil, non-matching rows dim so the graph topology stays intact (the
    /// lanes need both endpoints visible to make sense).
    var isMatch: ((Commit) -> Bool)? = nil
    let onSelect: (String) -> Void
    /// Fired when the user single-clicks the pinned "Uncommitted changes" row.
    /// Host wires it to its own selection state so the right detail panel and
    /// the bottom diff pane switch to working-copy mode.
    var onUncommittedSelect: (() -> Void)? = nil
    /// Triggered by a double-click on a commit row. Host views typically use
    /// it to checkout the commit (or its enclosing local branch).
    var onDoubleClick: ((String) -> Void)? = nil
    /// Fired with the last commit when the end of the list is on screen
    /// (`CommitRowList`). Host wires it to
    /// `HistoryStore.loadMoreIfNeeded(currentItem:)` so reaching the
    /// last loaded commit pulls in the next page. Without this hook the log
    /// silently stops at `pageSize` even though `hasMore` is true.
    var onAppear: ((Commit) -> Void)? = nil
    /// Fired when a `BranchChip` is dropped on a row (or on another chip).
    /// Host inspects `BranchDropContext` to decide between move / merge /
    /// rebase. `nil` disables drag-and-drop on this table.
    var onBranchDrop: ((DraggedBranch, BranchDropContext) -> Void)? = nil

    @Environment(\.appTheme) private var theme
    /// Ghosts turn opaque with it (`GraphStyle.ghostOpacity`).
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// The table takes keyboard focus when a row is clicked, so ↑ / ↓ can
    /// walk the history (a commit list a keyboard can't drive fails the HIG
    /// and leaves keyboard-only users stuck).
    @FocusState private var tableFocused: Bool
    /// Last selection made from inside the table (click / ↑↓). Those rows
    /// are already on screen, so only selections from elsewhere (sidebar,
    /// palette, reveal) scroll.
    @State private var localSelection: String?
    /// Last layout pass's `HistoryTableLayout.authorFits`, so Author comes
    /// back only with some room to spare.
    @State private var authorFits = true

    private var rowHeight: CGFloat { theme.density.metrics.rowList }

    /// With "Show scroll bars: Always" the vertical scroller takes width out
    /// of the viewport; without subtracting it the rows overflow by that
    /// much and a horizontal scroll bar appears for nothing.
    private static var legacyScrollerWidth: CGFloat {
        NSScroller.preferredScrollerStyle == .legacy
            ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
            : 0
    }
    /// Share of the table the lanes alone can claim while the graph sizes
    /// itself. With many parallel branches the full gutter pushed Description
    /// to its floor and the table into horizontal scrolling; past this the
    /// outer lanes clip.
    nonisolated static let maxAutomaticGraphShare: CGFloat = 0.35

    /// Width of the GRAPH column until the user drags it: the lanes' width,
    /// up to `maxAutomaticGraphShare` of `viewport`, never under the
    /// column's own minimum.
    nonisolated static func autoGraphWidth(lanesWidth: CGFloat, viewport: CGFloat, columnMin: CGFloat) -> CGFloat {
        max(columnMin, min(lanesWidth, viewport * maxAutomaticGraphShare))
    }

    /// Width of the GRAPH column as rendered: fitted to the lanes while it's
    /// auto-sized, else the user's. Lanes that don't fit clip (`CommitRow`).
    nonisolated static func graphWidth(isAuto: Bool, userWidth: CGFloat, lanesWidth: CGFloat,
                                       viewport: CGFloat, columnMin: CGFloat) -> CGFloat {
        isAuto
            ? autoGraphWidth(lanesWidth: lanesWidth, viewport: viewport, columnMin: columnMin)
            : max(columnMin, userWidth)
    }

    /// Graph look (graph v3 spec §5). Built once per render in `body`, which
    /// also resolves the role colours once for every row.
    private func makeGraphStyle() -> GraphStyle {
        GraphStyle(
            metrics: theme.density.metrics.graph,
            accent: theme.accentSwatch,
            accentColor: theme.colors.accent,
            dark: theme.effectiveMode == .dark,
            nodeFill: theme.colors.bgContent,
            ghostOpacity: GraphStyle.ghostOpacity(increasedContrast: theme.increasedContrast,
                                                  reduceTransparency: reduceTransparency)
        )
    }

    /// Rendered width of the GRAPH column (`graphWidth`).
    private func graphGutterWidth(viewport: CGFloat) -> CGFloat {
        let metricsOnly = GraphStyle(metrics: theme.density.metrics.graph)
        return Self.graphWidth(isAuto: columns.isAutoWidth("graph"),
                               userWidth: columns.width("graph"),
                               lanesWidth: metricsOnly.gutterWidth(lanes: maxLanes),
                               viewport: viewport,
                               columnMin: columns.minWidth("graph"))
    }

    /// Binding for the GRAPH handle: reads the rendered width, so a drag
    /// starts where the column is even while it fits its lanes, and writes
    /// the user's width (from then on the column is theirs).
    private func graphHandleBinding(rendered: CGFloat) -> Binding<CGFloat> {
        let stored = columns.binding(for: "graph")
        return Binding(
            get: { rendered },
            set: { stored.wrappedValue = $0 }
        )
    }

    var body: some View {
        let style = makeGraphStyle()
        return GeometryReader { geo in
            // Resolve the derived widths once per render, not once per row.
            let viewport = geo.size.width - Self.legacyScrollerWidth
            let gutterWidth = graphGutterWidth(viewport: viewport)
            let layout = HistoryTableLayout(
                viewport: viewport,
                graph: gutterWidth,
                author: columns.width("author"),
                date: columns.width("when"),
                commit: columns.width("sha"),
                hidden: columns.hiddenHistoryColumns,
                authorFitted: authorFits
            )
            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal], showsIndicators: true) {
                    LazyVStack(spacing: HistoryTableLayout.rowSpacing, pinnedViews: [.sectionHeaders]) {
                        Section {
                            if showsUncommittedRow {
                                UncommittedRow(
                                    rowHeight: rowHeight,
                                    layout: layout,
                                    isSelected: uncommittedSelected,
                                    onSelect: { onUncommittedSelect?() },
                                    connector: uncommittedStep,
                                    graphStyle: style,
                                    maxLanes: maxLanes
                                )
                            }
                            // Rows are identified by sha (see `CommitRowList`);
                            // `scrollTo(sha)` below relies on it.
                            CommitRowList(commits: commits, revision: logRevision, onLastRowAppear: onAppear) { idx, commit in
                                CommitRow(
                                    commit: commit,
                                    layout: layouts[safe: idx] ?? .empty,
                                    maxLanes: maxLanes,
                                    rowHeight: rowHeight,
                                    tableLayout: layout,
                                    chips: refChips,
                                    currentBranch: currentBranch,
                                    isSelected: commit.sha == selectedSha,
                                    graphStyle: style,
                                    isHeadCommit: commit.sha == headSha,
                                    dimmed: isMatch.map { !$0(commit) } ?? false,
                                    onSelect: {
                                        tableFocused = true
                                        localSelection = commit.sha
                                        onSelect(commit.sha)
                                    },
                                    onDoubleClick: { onDoubleClick?(commit.sha) },
                                    onBranchDrop: onBranchDrop
                                )
                                .equatable()
                            }
                        } header: {
                            CommitTableHeader(
                                layout: layout,
                                graphHandle: graphHandleBinding(rendered: gutterWidth),
                                graphMinWidth: columns.minWidth("graph"),
                                onFitGraph: { columns.resetWidth("graph") },
                                columns: columns
                            )
                        }
                    }
                    .frame(width: max(layout.totalWidth, geo.size.width - Self.legacyScrollerWidth), alignment: .leading)
                    .frame(minHeight: geo.size.height, alignment: .topLeading)
                }
                .focusable()
                .focusEffectDisabled()
                .focused($tableFocused)
                .onChange(of: layout.authorFits) { _, fits in authorFits = fits }
                .onKeyPress(.downArrow) { moveSelection(by: 1, proxy: proxy) }
                .onKeyPress(.upArrow) { moveSelection(by: -1, proxy: proxy) }
                .onChange(of: selectedSha, initial: true) { _, sha in
                    guard let sha, sha != localSelection else { return }
                    // A selection made elsewhere (sidebar branch tree, palette,
                    // reveal) brings its row into view. `initial: true` covers
                    // the reveal that switches to History, where the table
                    // mounts with the selection already set; the hop to the
                    // next run-loop turn lets the lazy stack lay out first.
                    // x: 0 keeps the graph in view.
                    Task { @MainActor in proxy.scrollTo(sha, anchor: UnitPoint(x: 0, y: 0.5)) }
                }
            }
        }
    }

    /// Selects the commit `offset` rows away from the current selection (the
    /// first row when nothing is selected yet) and scrolls it into view.
    private func moveSelection(by offset: Int, proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !commits.isEmpty else { return .ignored }
        let current = selectedSha.flatMap { sha in commits.firstIndex { $0.sha == sha } }
        let target = current.map { min(max($0 + offset, 0), commits.count - 1) } ?? 0
        let sha = commits[target].sha
        guard sha != selectedSha else { return .handled }
        localSelection = sha
        onSelect(sha)
        proxy.scrollTo(sha)
        return .handled
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var columns = ResizableTableModel.historyColumns(id: "history.preview")
    let vm = RepositoryViewModel.preview
    CommitGraphTable(
        commits: vm.history.commits,
        layouts: vm.history.graphLayouts,
        maxLanes: vm.history.graphMaxLanes,
        refChips: vm.history.refChips,
        currentBranch: vm.currentBranchName,
        selectedSha: vm.history.commits.first?.sha,
        showsUncommittedRow: vm.history.showsUncommittedRow,
        uncommittedStep: vm.history.uncommittedStep,
        columns: columns,
        onSelect: { _ in }
    )
    .frame(width: 920, height: 480)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
