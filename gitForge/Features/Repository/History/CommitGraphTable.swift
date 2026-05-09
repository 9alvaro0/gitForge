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

private struct CommitTableHeader: View {
    let gutterWidth: CGFloat
    let graphHandle: Binding<CGFloat>
    let graphMinWidth: CGFloat
    let columns: ResizableTableModel

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.none) {
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
        .padding(.horizontal, DesignTokens.Spacing.xxxxl)
        .frame(height: DesignTokens.Control.height)
        .background(theme.palette.bg1)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line).frame(height: DesignTokens.Stroke.regular) }
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
        HStack(spacing: DesignTokens.Spacing.none) {
            HStack(spacing: DesignTokens.Spacing.none) {
                Spacer().frame(width: DesignTokens.IconSize.xl)
                Rectangle().fill(theme.palette.mod).frame(width: DesignTokens.Spacing.md, height: DesignTokens.Spacing.md)
                    .overlay(Rectangle().stroke(theme.palette.mod, lineWidth: DesignTokens.Stroke.regular))
            }
            .frame(width: gutterWidth, alignment: .leading)
            Color.clear.frame(width: DesignTokens.Spacing.md)
            Color.clear.frame(width: columns.width("branchTag"))
            Color.clear.frame(width: DesignTokens.Spacing.md)
            HStack(spacing: DesignTokens.Spacing.md) {
                Circle().fill(theme.palette.mod).frame(width: DesignTokens.Spacing.md, height: DesignTokens.Spacing.md)
                Text("Uncommitted changes")
                    .font(AppFont.sans(12.5))
                    .italic()
                    .foregroundStyle(theme.palette.mod)
            }
            .frame(width: columns.width("message"), alignment: .leading)
            Color.clear.frame(width: DesignTokens.Spacing.md)
            Text("").frame(width: columns.width("author"))
            Color.clear.frame(width: DesignTokens.Spacing.md)
            Text("–")
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
                .frame(width: columns.width("sha"), alignment: .leading)
            Color.clear.frame(width: DesignTokens.Spacing.md)
            Text("now")
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
                .frame(width: columns.width("when"), alignment: .trailing)
            Color.clear.frame(width: DesignTokens.Spacing.md)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignTokens.Spacing.xxxxl)
        .frame(height: rowHeight)
        .background(LinearGradient(colors: [theme.palette.mod.opacity(DesignTokens.Opacity.faint), .clear], startPoint: .leading, endPoint: .trailing))
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
    let onBranchDrop: ((DraggedBranch, BranchDropContext) -> Void)?

    @Environment(\.appTheme) private var theme
    @State private var showHiddenRefs = false
    @State private var rowDropTargeted = false

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.none) {
            graphGutter
                .frame(width: gutterWidth, alignment: .leading)
            Color.clear.frame(width: DesignTokens.Spacing.md)
            branchTagColumn
                .frame(width: columns.width("branchTag"), alignment: .leading)
            Color.clear.frame(width: DesignTokens.Spacing.md)
            messageColumn
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
            Text(relativeWhen)
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

    /// Re-uses the existing `GraphColumnView` so lane drawing matches the rest of the app.
    private var graphGutter: some View {
        HStack(spacing: DesignTokens.Spacing.none) {
            Spacer().frame(width: DesignTokens.IconSize.xl)
            GraphColumnView(row: layout, maxLanes: max(maxLanes, 1))
        }
    }

    /// Up to 2 chips when refs ≤ 2, otherwise first chip + "+N" overflow pill.
    /// Refs are sorted so the current branch wins, then local, tag, remote.
    private var branchTagColumn: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            ForEach(visibleRefs) { ref in
                chipView(for: ref)
            }
            if let extra = overflowCount {
                overflowPill(count: extra)
            }
            Spacer(minLength: 0)
        }
    }

    /// Local-branch chips become draggable (drag source) and drop targets
    /// (chip→chip merge/rebase). Remote and tag chips render plain — drag is
    /// gated to local branches in the v1 of this feature, and remote/tag drops
    /// don't have a meaningful action attached.
    @ViewBuilder
    private func chipView(for ref: GitRef) -> some View {
        let isCurrent = ref.isLocalBranch && ref.name == currentBranch
        let chip = BranchChip(
            name: ref.displayName,
            current: isCurrent,
            remote: ref.isRemoteBranch,
            tag: ref.isTag,
            hasRemoteCounterpart: hasRemoteCounterpart(for: ref)
        )
        if ref.isLocalBranch, let onBranchDrop {
            chip
                .draggable(DraggedBranch(
                    name: ref.name,
                    isCurrent: isCurrent,
                    isLocal: true,
                    sourceSha: commit.sha
                ))
                .modifier(ChipDropModifier(
                    targetBranchName: ref.name,
                    targetSha: commit.sha,
                    onDrop: { dropped in
                        onBranchDrop(dropped, .onBranch(targetBranchName: ref.name, targetSha: commit.sha))
                    }
                ))
        } else {
            chip
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
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.hairline)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.chip)
                        .fill(showHiddenRefs ? theme.palette.bg4 : theme.palette.bg3)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.chip)
                        .stroke(theme.palette.lineStrong, lineWidth: DesignTokens.Stroke.regular)
                )
                .contentShape(.rect(cornerRadius: DesignTokens.Radius.chip))
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
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
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
        .padding(DesignTokens.Spacing.xl)
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
        if rowDropTargeted { return theme.palette.accent.opacity(DesignTokens.Opacity.subtle) }
        if isSelected { return theme.palette.accentSoft }
        return .clear
    }

    private var relativeWhen: String {
        theme.dateDisplayMode.format(commit.authorDate)
    }
}

/// Wraps `.dropDestination` for a commit row. Extracted as a `ViewModifier`
/// so the row's `body` stays simple — chained drop modifiers used to push the
/// type-checker past its limit when combined with the rest of the row's
/// modifier stack.
private struct RowDropModifier: ViewModifier {
    let enabled: Bool
    let targetSha: String
    @Binding var isTargeted: Bool
    let onDrop: (DraggedBranch) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.dropDestination(for: DraggedBranch.self) { items, _ in
                guard let dropped = items.first else { return false }
                // Drop on the row the chip already lives on is a no-op — skip
                // the dialog so the user doesn't see a confirm for nothing.
                guard dropped.sourceSha != targetSha else { return false }
                onDrop(dropped)
                return true
            } isTargeted: { hovered in
                isTargeted = hovered
            }
        } else {
            content
        }
    }
}

/// Drop target for chip→chip drops (merge / rebase). The target chip's
/// `dropDestination` wins over the row's because it's the innermost handler
/// — that's the GitKraken-style "drop on the chip = pick a branch action".
private struct ChipDropModifier: ViewModifier {
    let targetBranchName: String
    let targetSha: String
    let onDrop: (DraggedBranch) -> Void

    @State private var hovered = false
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovered ? 1.06 : 1.0)
            .shadow(color: hovered ? theme.palette.accent.opacity(0.45) : .clear, radius: 4)
            .animation(.easeOut(duration: 0.12), value: hovered)
            .dropDestination(for: DraggedBranch.self) { items, _ in
                guard let dropped = items.first else { return false }
                // Dropping a branch on its own chip is a no-op.
                guard dropped.name != targetBranchName else { return false }
                onDrop(dropped)
                return true
            } isTargeted: { isHovered in
                hovered = isHovered
            }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#if DEBUG
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
#endif
