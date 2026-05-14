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

    private var maxLanes: Int {
        layouts.map(\.totalLanes).max() ?? 1
    }
    private var rowHeight: CGFloat { theme.density.rowHeight }
    /// Smallest the GRAPH gutter can ever shrink to without clipping lanes.
    /// Grows with the number of simultaneously alive lanes so a wide history
    /// (e.g. many parallel `release/*` branches) is never cramped, and floors
    /// at the column's static minimum so the user can still drag it tighter
    /// than 110 when the history is single-lane.
    private var dynamicGraphMin: CGFloat {
        let lanes = max(maxLanes, 1)
        let laneWidth: CGFloat = 14
        let leadingSpacer: CGFloat = 18
        let trailingPad: CGFloat = 8
        let needed = leadingSpacer + CGFloat(lanes) * laneWidth + trailingPad
        return max(columns.minWidth("graph"), needed)
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

    /// Sum of every fixed-width piece in a row (six resizable columns +
    /// six 8pt handle gaps + 36pt horizontal padding). When the viewport is
    /// wider, a trailing Spacer absorbs the slack; when it's narrower,
    /// ScrollView's horizontal axis takes over.
    private var totalContentWidth: CGFloat {
        let columnsWidth: CGFloat = columns.width("branchTag")
            + columns.width("message")
            + columns.width("author")
            + columns.width("sha")
            + columns.width("when")
        let handleGaps: CGFloat = 6 * 8
        let horizontalPadding: CGFloat = 36
        return graphGutterWidth + columnsWidth + handleGaps + horizontalPadding
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView([.vertical, .horizontal], showsIndicators: true) {
                LazyVStack(spacing: DesignTokens.Spacing.none, pinnedViews: [.sectionHeaders]) {
                    Section {
                        if workingCopyDirty {
                            UncommittedRow(
                                rowHeight: rowHeight,
                                gutterWidth: graphGutterWidth,
                                columns: columns,
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
                                gutterWidth: graphGutterWidth,
                                refs: refsBySha[commit.sha] ?? [],
                                currentBranch: currentBranch,
                                isSelected: commit.sha == selectedSha,
                                dimmed: isMatch.map { !$0(commit) } ?? false,
                                columns: columns,
                                onSelect: { onSelect(commit.sha) },
                                onDoubleClick: { onDoubleClick?(commit.sha) },
                                onBranchDrop: onBranchDrop
                            )
                            .onAppear { onAppear?(commit) }
                        }
                    } header: {
                        CommitTableHeader(
                            gutterWidth: graphGutterWidth,
                            graphHandle: graphHandleBinding,
                            graphMinWidth: dynamicGraphMin,
                            columns: columns
                        )
                    }
                }
                .frame(width: max(totalContentWidth, geo.size.width), alignment: .leading)
                .frame(minHeight: geo.size.height, alignment: .topLeading)
            }
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var columns = ResizableTableModel(
        id: "history.preview",
        columns: [
            (id: "graph",     defaultWidth: 110, minWidth: 80),
            (id: "branchTag", defaultWidth: 220, minWidth: 80),
            (id: "message",   defaultWidth: 480, minWidth: 240),
            (id: "author",    defaultWidth: 130, minWidth: 80),
            (id: "sha",       defaultWidth: 80,  minWidth: 60),
            (id: "when",      defaultWidth: 70,  minWidth: 50),
        ]
    )
    let vm = RepositoryViewModel.preview
    CommitGraphTable(
        commits: vm.commits,
        layouts: vm.graphLayouts,
        refsBySha: vm.refsBySha,
        currentBranch: vm.currentBranchName,
        selectedSha: vm.commits.first?.sha,
        workingCopyDirty: !vm.status.isClean,
        columns: columns,
        onSelect: { _ in }
    )
    .frame(width: 920, height: 480)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
