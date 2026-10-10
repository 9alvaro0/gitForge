import SwiftUI

/// Header + data table for the History view. Owns its own dual-axis ScrollView
/// so columns line up between header and rows even when the graph gutter is
/// wide enough to push the row past the viewport — horizontal scroll engages
/// automatically. The header is pinned via a `LazyVStack` Section so it stays
/// at the top during vertical scroll and slides with content during horizontal
/// scroll (so the labels never desync from the columns below).
///
/// Drag-handle convention: each handle sits on the RIGHT (trailing) edge of
/// the column it controls — Excel-style. Drag right = that column widens, the
/// next column slides over. Every visible column has a handle including GRAPH
/// and WHEN, so any boundary the eye lands on is draggable.
struct CommitGraphTable: View {
    let commits: [Commit]
    let layouts: [GraphRowLayout]
    /// Widest row of the graph (`RepositoryViewModel.graphMaxLanes`, computed
    /// once per layout pass). Recomputing it here walked every layout, and
    /// did so for each row SwiftUI built — O(visible rows × commits) on every
    /// re-render of History.
    let maxLanes: Int
    let refsBySha: [String: [GitRef]]
    let currentBranch: String?
    let selectedSha: Commit.ID?
    let workingCopyDirty: Bool
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
    /// Fired when a row appears in the viewport. Host wires it to
    /// `RepositoryViewModel.loadMoreIfNeeded(currentItem:)` so reaching the
    /// last loaded commit pulls in the next page. Without this hook the log
    /// silently stops at `pageSize` even though `hasMore` is true.
    var onAppear: ((Commit) -> Void)? = nil
    /// Fired when a `BranchChip` is dropped on a row (or on another chip).
    /// Host inspects `BranchDropContext` to decide between move / merge /
    /// rebase. `nil` disables drag-and-drop on this table.
    var onBranchDrop: ((DraggedBranch, BranchDropContext) -> Void)? = nil

    @Environment(\.appTheme) private var theme
    /// The table takes keyboard focus when a row is clicked, so ↑ / ↓ can
    /// walk the history (a commit list a keyboard can't drive fails the HIG
    /// and leaves keyboard-only users stuck).
    @FocusState private var tableFocused: Bool

    private var rowHeight: CGFloat { theme.density.metrics.rowList }

    /// With "Show scroll bars: Always" the vertical scroller takes width out
    /// of the viewport; without subtracting it the rows overflow by that
    /// much and a horizontal scroll bar appears for nothing.
    private static var legacyScrollerWidth: CGFloat {
        NSScroller.preferredScrollerStyle == .legacy
            ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
            : 0
    }
    /// Smallest the GRAPH gutter can ever shrink to without clipping lanes.
    /// Grows with the number of simultaneously alive lanes so a wide history
    /// (e.g. many parallel `release/*` branches) is never cramped, and floors
    /// at the column's static minimum so the user can still drag it tighter
    /// than 110 when the history is single-lane.
    private var dynamicGraphMin: CGFloat {
        max(columns.minWidth("graph"), graphStyle.gutterWidth(lanes: maxLanes))
    }

    /// v2 graph look (spec §4.5), resolved once per render.
    private var graphStyle: GraphStyle {
        let headSha = refsBySha.first { _, refs in
            refs.contains { $0.isLocalBranch && $0.name == currentBranch }
        }?.key
        return GraphStyle(
            metrics: theme.density.metrics.graph,
            accent: theme.accentSwatch,
            accentColor: theme.colors.accent,
            dark: theme.effectiveMode == .dark,
            nodeFill: theme.colors.bgContent,
            headBranchId: GraphHead.branchId(headSha: headSha, commits: commits, layouts: layouts)
        )
    }

    /// Effective rendered width of the GRAPH gutter. Honors the user's stored
    /// preference but bumps up to `dynamicGraphMin` so lanes never overflow
    /// into the next column when commits arrive.
    private var graphGutterWidth: CGFloat {
        max(columns.width("graph"), dynamicGraphMin)
    }

    /// Custom binding for the GRAPH handle that mirrors `graphGutterWidth` —
    /// reads the effective (clamped) value so the handle visually starts where
    /// the gutter actually is, and writes back through the same clamp so a
    /// drag-left below `dynamicGraphMin` snaps the stored value to the floor
    /// instead of silently sliding under it.
    private var graphHandleBinding: Binding<CGFloat> {
        let dynMin = dynamicGraphMin
        let stored = columns.binding(for: "graph")
        return Binding(
            get: { max(stored.wrappedValue, dynMin) },
            set: { stored.wrappedValue = max($0, dynMin) }
        )
    }

    var body: some View {
        // Resolve the derived widths once per render, not once per row.
        let gutterWidth = graphGutterWidth
        let style = graphStyle
        let headSha = commits.first { commit in
            (refsBySha[commit.sha] ?? []).contains { $0.isLocalBranch && $0.name == currentBranch }
        }?.sha
        return GeometryReader { geo in
            let layout = HistoryTableLayout(
                viewport: geo.size.width - Self.legacyScrollerWidth,
                graph: gutterWidth,
                author: columns.width("author"),
                date: columns.width("when"),
                commit: columns.width("sha")
            )
            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal], showsIndicators: true) {
                    LazyVStack(spacing: 1, pinnedViews: [.sectionHeaders]) {
                        Section {
                            if workingCopyDirty {
                                UncommittedRow(
                                    rowHeight: rowHeight,
                                    layout: layout,
                                    isSelected: uncommittedSelected,
                                    onSelect: { onUncommittedSelect?() }
                                )
                            }
                            ForEach(Array(commits.enumerated()), id: \.element.sha) { idx, commit in
                                CommitRow(
                                    commit: commit,
                                    layout: layouts[safe: idx] ?? .empty,
                                    maxLanes: maxLanes,
                                    rowHeight: rowHeight,
                                    tableLayout: layout,
                                    refs: refsBySha[commit.sha] ?? [],
                                    currentBranch: currentBranch,
                                    isSelected: commit.sha == selectedSha,
                                    graphStyle: style,
                                    isHeadCommit: commit.sha == headSha,
                                    dimmed: isMatch.map { !$0(commit) } ?? false,
                                    onSelect: {
                                        tableFocused = true
                                        onSelect(commit.sha)
                                    },
                                    onDoubleClick: { onDoubleClick?(commit.sha) },
                                    onBranchDrop: onBranchDrop
                                )
                                .onAppear { onAppear?(commit) }
                            }
                        } header: {
                            CommitTableHeader(
                                layout: layout,
                                graphHandle: graphHandleBinding,
                                graphMinWidth: dynamicGraphMin,
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
                .onKeyPress(.downArrow) { moveSelection(by: 1, proxy: proxy) }
                .onKeyPress(.upArrow) { moveSelection(by: -1, proxy: proxy) }
                // A selection made elsewhere (sidebar branch tree, palette)
                // must bring its row into view. `initial: true` covers the
                // reveal that switches to History: the table mounts with the
                // selection already set, so a plain onChange never fires.
                // The hop to the next run-loop turn lets the lazy stack lay
                // out first. A click on a visible row is a no-op scroll.
                .onChange(of: selectedSha, initial: true) { _, sha in
                    guard let sha else { return }
                    // x: 0 pins the leading edge, so a reveal never scrolls
                    // the table sideways and hides the graph.
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
        commits: vm.commits,
        layouts: vm.graphLayouts,
        maxLanes: vm.graphMaxLanes,
        refsBySha: vm.refsBySha,
        currentBranch: vm.currentBranchName,
        selectedSha: vm.commits.first?.sha,
        workingCopyDirty: !vm.status.isClean,
        columns: columns,
        onSelect: { _ in }
    )
    .frame(width: 920, height: 480)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
