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
    let columns: ResizableTableModel
    /// `nil` when search is inactive — every row renders at full opacity. When
    /// non-nil, non-matching rows dim so the graph topology stays intact (the
    /// lanes need both endpoints visible to make sense).
    var isMatch: ((Commit) -> Bool)? = nil
    let onSelect: (String) -> Void
    /// Triggered by a double-click on a commit row. Host views typically use it
    /// to checkout the commit (or its enclosing local branch).
    var onDoubleClick: ((String) -> Void)? = nil
    /// Fired when a row appears in the viewport. Host wires it to
    /// `RepositoryViewModel.loadMoreIfNeeded(currentItem:)` so reaching the
    /// last loaded commit pulls in the next page. Without this hook the log
    /// silently stops at `pageSize` even though `hasMore` is true.
    var onAppear: ((Commit) -> Void)? = nil

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
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        if workingCopyDirty {
                            UncommittedRow(
                                rowHeight: rowHeight,
                                gutterWidth: graphGutterWidth,
                                columns: columns
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
                                onDoubleClick: { onDoubleClick?(commit.sha) }
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

private struct CommitTableHeader: View {
    let gutterWidth: CGFloat
    let graphHandle: Binding<CGFloat>
    let graphMinWidth: CGFloat
    let columns: ResizableTableModel

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            Text("GRAPH").frame(width: gutterWidth, alignment: .leading)
            ColumnDragHandle(width: graphHandle,
                             minWidth: graphMinWidth, maxWidth: 600,
                             onCommit: { columns.commit() })
            Text("BRANCH / TAG")
                .frame(width: columns.width("branchTag"), alignment: .leading)
            ColumnDragHandle(width: columns.binding(for: "branchTag"),
                             minWidth: columns.minWidth("branchTag"), maxWidth: 480,
                             onCommit: { columns.commit() })
            Text("MESSAGE")
                .frame(width: columns.width("message"), alignment: .leading)
            ColumnDragHandle(width: columns.binding(for: "message"),
                             minWidth: columns.minWidth("message"), maxWidth: 1200,
                             onCommit: { columns.commit() })
            Text("AUTHOR")
                .frame(width: columns.width("author"), alignment: .leading)
            ColumnDragHandle(width: columns.binding(for: "author"),
                             minWidth: columns.minWidth("author"), maxWidth: 280,
                             onCommit: { columns.commit() })
            Text("SHA")
                .frame(width: columns.width("sha"), alignment: .leading)
            ColumnDragHandle(width: columns.binding(for: "sha"),
                             minWidth: columns.minWidth("sha"), maxWidth: 200,
                             onCommit: { columns.commit() })
            Text("WHEN")
                .frame(width: columns.width("when"), alignment: .trailing)
            ColumnDragHandle(width: columns.binding(for: "when"),
                             minWidth: columns.minWidth("when"), maxWidth: 160,
                             onCommit: { columns.commit() })
            Spacer(minLength: 0)
        }
        .font(AppFont.mono(10.5, family: theme.monoFont))
        .tracking(0.6)
        .foregroundStyle(theme.palette.fg3)
        .padding(.horizontal, 18)
        .frame(height: 28)
        .background(theme.palette.bg1)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line).frame(height: 1) }
        .contextMenu {
            Button("Reset column widths") { columns.reset() }
        }
    }
}

private struct UncommittedRow: View {
    let rowHeight: CGFloat
    let gutterWidth: CGFloat
    let columns: ResizableTableModel

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer().frame(width: 18)
                Rectangle().fill(theme.palette.mod).frame(width: 8, height: 8)
                    .overlay(Rectangle().stroke(theme.palette.mod, lineWidth: 1))
            }
            .frame(width: gutterWidth, alignment: .leading)
            Color.clear.frame(width: 8)
            Color.clear.frame(width: columns.width("branchTag"))
            Color.clear.frame(width: 8)
            HStack(spacing: 8) {
                Circle().fill(theme.palette.mod).frame(width: 8, height: 8)
                Text("Uncommitted changes")
                    .font(AppFont.sans(12.5))
                    .italic()
                    .foregroundStyle(theme.palette.mod)
            }
            .frame(width: columns.width("message"), alignment: .leading)
            Color.clear.frame(width: 8)
            Text("").frame(width: columns.width("author"))
            Color.clear.frame(width: 8)
            Text("–")
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
                .frame(width: columns.width("sha"), alignment: .leading)
            Color.clear.frame(width: 8)
            Text("now")
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
                .frame(width: columns.width("when"), alignment: .trailing)
            Color.clear.frame(width: 8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(height: rowHeight)
        .background(LinearGradient(colors: [theme.palette.mod.opacity(0.07), .clear], startPoint: .leading, endPoint: .trailing))
    }
}

private struct CommitRow: View {
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

    @Environment(\.appTheme) private var theme
    @State private var showHiddenRefs = false

    var body: some View {
        HStack(spacing: 0) {
            graphGutter
                .frame(width: gutterWidth, alignment: .leading)
            Color.clear.frame(width: 8)
            branchTagColumn
                .frame(width: columns.width("branchTag"), alignment: .leading)
            Color.clear.frame(width: 8)
            messageColumn
                .frame(width: columns.width("message"), alignment: .leading)
            Color.clear.frame(width: 8)
            HStack(spacing: 6) {
                Avatar(name: commit.authorName, size: 16, colorSeed: commit.authorEmail)
                Text(commit.authorName)
                    .font(AppFont.sans(12))
                    .foregroundStyle(theme.palette.fg2)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: columns.width("author"), alignment: .leading)
            Color.clear.frame(width: 8)
            Text(commit.shortSha)
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
                .frame(width: columns.width("sha"), alignment: .leading)
            Color.clear.frame(width: 8)
            Text(relativeWhen)
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
                .frame(width: columns.width("when"), alignment: .trailing)
            Color.clear.frame(width: 8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(height: rowHeight)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if isSelected { Rectangle().fill(theme.palette.accent).frame(width: 2) }
        }
        .opacity(dimmed ? 0.35 : 1)
        .contentShape(.rect)
        .onTapGesture(count: 2, perform: onDoubleClick)
        .onTapGesture(perform: onSelect)
    }

    /// Re-uses the existing `GraphColumnView` so lane drawing matches the rest of the app.
    private var graphGutter: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 18)
            GraphColumnView(row: layout, maxLanes: max(maxLanes, 1))
        }
    }

    /// Up to 2 chips when refs ≤ 2, otherwise first chip + "+N" overflow pill.
    /// Refs are sorted so the current branch wins, then local, tag, remote.
    private var branchTagColumn: some View {
        HStack(spacing: 4) {
            ForEach(visibleRefs) { ref in
                BranchChip(
                    name: ref.displayName,
                    current: ref.isLocalBranch && ref.name == currentBranch,
                    remote: ref.isRemoteBranch,
                    tag: ref.isTag,
                    hasRemoteCounterpart: hasRemoteCounterpart(for: ref)
                )
            }
            if let extra = overflowCount {
                overflowPill(count: extra)
            }
            Spacer(minLength: 0)
        }
    }

    /// Names of local branches present on this commit. Remote-tracking refs
    /// whose `displayName` matches one of these are deduplicated — the local
    /// chip gets the cloud icon trailing it instead of producing a second
    /// chip with the same name.
    private var localBranchNames: Set<String> {
        Set(refs.filter(\.isLocalBranch).map(\.displayName))
    }

    private func hasRemoteCounterpart(for ref: GitRef) -> Bool {
        guard ref.isLocalBranch else { return false }
        return refs.contains { $0.isRemoteBranch && $0.displayName == ref.displayName }
    }

    private var sortedRefs: [GitRef] {
        let names = localBranchNames
        return refs
            .filter { ref in
                // Drop remote-tracking ref if a local branch with the same name
                // is also on this commit — they collapse into a single chip.
                !(ref.isRemoteBranch && names.contains(ref.displayName))
            }
            .sorted { a, b in
                let aCurrent = a.isLocalBranch && a.name == currentBranch
                let bCurrent = b.isLocalBranch && b.name == currentBranch
                if aCurrent != bCurrent { return aCurrent }
                let aWeight = Self.refWeight(a)
                let bWeight = Self.refWeight(b)
                if aWeight != bWeight { return aWeight < bWeight }
                return a.displayName < b.displayName
            }
    }

    private static func refWeight(_ ref: GitRef) -> Int {
        if ref.isLocalBranch  { return 0 }
        if ref.isTag          { return 1 }
        if ref.isRemoteBranch { return 2 }
        return 3
    }

    private var visibleRefs: [GitRef] {
        sortedRefs.count <= 2 ? sortedRefs : Array(sortedRefs.prefix(1))
    }

    private var hiddenRefs: [GitRef] {
        Array(sortedRefs.dropFirst(visibleRefs.count))
    }

    private var overflowCount: Int? {
        hiddenRefs.isEmpty ? nil : hiddenRefs.count
    }

    @ViewBuilder
    private func overflowPill(count: Int) -> some View {
        Button {
            showHiddenRefs.toggle()
        } label: {
            Text("+\(count)")
                .font(AppFont.mono(10.5, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(showHiddenRefs ? theme.palette.bg4 : theme.palette.bg3)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(theme.palette.lineStrong, lineWidth: 1)
                )
                .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { showHiddenRefs = true }
        }
        .popover(isPresented: $showHiddenRefs, arrowEdge: .bottom) {
            hiddenRefsPopover
        }
    }

    private var hiddenRefsPopover: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(hiddenRefs.count) more")
                .font(AppFont.sans(11, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(theme.palette.fg3)
            ForEach(hiddenRefs) { ref in
                BranchChip(
                    name: ref.displayName,
                    current: ref.isLocalBranch && ref.name == currentBranch,
                    remote: ref.isRemoteBranch,
                    tag: ref.isTag,
                    hasRemoteCounterpart: hasRemoteCounterpart(for: ref)
                )
            }
        }
        .padding(12)
        .background(theme.palette.bg2)
        .appTheme(theme)
    }

    private var messageColumn: some View {
        Text(commit.subject)
            .font(AppFont.sans(12.5))
            .foregroundStyle(theme.palette.fg1)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rowBackground: Color {
        if isSelected { return theme.palette.accentSoft }
        return .clear
    }

    private var relativeWhen: String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
        return f.localizedString(for: commit.authorDate, relativeTo: .now)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
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
