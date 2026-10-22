import SwiftUI

/// Top-level History pane: the commit table on the left, the inspector
/// (commit detail over the selected file's diff) on the right (redesign
/// spec §6.2). Owns the resizable layout state (panel widths / collapsed
/// flags / column widths) and routes drag-drop / double-click events into
/// the right confirmation dialogs (action runners live in
/// `HistoryView+Actions.swift`).
struct HistoryView: View {
    @Bindable var viewModel: RepositoryViewModel
    @Environment(\.appTheme) var theme
    @Environment(\.appPreferences) var preferences
    @Environment(AppState.self) var appState

    @State var search: String = ""
    /// Focus mode: rows outside this commit's history are dimmed.
    @State private var focus: HistoryFocus?
    /// Set when the user double-clicks a commit that no local branch points
    /// at. Drives the "checkout will be detached" confirmation dialog.
    @State var detachedCheckoutTarget: Commit?
    /// Drag-and-drop pending actions — one of these is set when a `BranchChip`
    /// is dropped on a row or another chip. Each drives its own confirmation
    /// dialog. Only one is set at a time per drop.
    @State var moveBranchRequest: MoveBranchRequest?
    @State var resetHeadRequest: ResetHeadRequest?
    @State var mergeRebaseRequest: MergeRebaseRequest?
    /// `nil` until the user toggles Unified/Split locally. While it stays nil
    /// the pane reads `preferences.defaultDiffMode` so changes in Settings show up
    /// immediately and re-entering History always lands on the default.
    @State private var diffModeOverride: DiffPane.ViewMode?
    /// `true` while the pinned "Uncommitted changes" row is the active selection.
    /// Drives both the right detail panel (working-copy file list) and the
    /// bottom diff pane (working-copy diff for the selected file).
    @State private var isUncommittedSelected: Bool = false
    /// Drop target under a dragged branch chip, shown in the intent HUD.
    @State var dropTracker = BranchDropTracker()

    @State private var columns = ResizableTableModel.historyColumns()

    private static let diffHeightKey = "gitForge.history.diffPaneHeight"
    private static let detailWidthKey = "gitForge.history.detailPanelWidth"
    private static let diffCollapsedKey = "gitForge.history.diffPaneCollapsed"
    private static let detailCollapsedKey = "gitForge.history.detailPanelCollapsed"
    private static let collapsedThreshold: CGFloat = 80
    private static let defaultDiffHeight: CGFloat = 340
    private static let minDetailWidth: CGFloat = 320
    private static let maxDetailWidth: CGFloat = 760
    /// Spec §4.6: inspector 480; the table keeps at least this much.
    private static let defaultDetailWidth: CGFloat = 480
    private static let minTableWidth: CGFloat = 520

    @State private var diffPaneHeight: CGFloat = {
        let stored = UserDefaults.standard.double(forKey: HistoryView.diffHeightKey)
        return stored > 0 ? CGFloat(stored) : HistoryView.defaultDiffHeight
    }()

    @State private var detailColumnWidth: CGFloat = {
        let stored = UserDefaults.standard.double(forKey: HistoryView.detailWidthKey)
        let resolved = stored > 0 ? CGFloat(stored) : HistoryView.defaultDetailWidth
        return min(max(HistoryView.minDetailWidth, resolved), HistoryView.maxDetailWidth)
    }()

    @State private var diffPaneCollapsed: Bool = UserDefaults.standard.bool(forKey: HistoryView.diffCollapsedKey)
    @State private var detailColumnCollapsed: Bool = UserDefaults.standard.bool(forKey: HistoryView.detailCollapsedKey)

    private var diffMode: Binding<DiffPane.ViewMode> {
        Binding(
            get: { diffModeOverride ?? preferences.defaultDiffMode },
            set: { diffModeOverride = $0 }
        )
    }

    var body: some View {
        // Build the search matcher once so the count below and the filter
        // pass to the table share the same closure (and the same single
        // O(n) walk over commits when search is active).
        let matcher = combinedMatcher
        let matchCount = matcher.map { fn in viewModel.history.commits.lazy.filter(fn).count }
            ?? viewModel.history.commits.count

        return VStack(spacing: 0) {
            HistoryFiltersBar(
                search: $search,
                totalCount: viewModel.history.commits.count,
                matchCount: matchCount,
                focusLabel: focus?.label,
                canFocus: viewModel.history.selectedCommit != nil,
                onToggleFocus: toggleFocus,
                showsRemoteBranches: viewModel.history.showsRemoteBranches,
                onToggleRemoteBranches: toggleRemoteBranches
            )
            GeometryReader { geo in
                HStack(spacing: 0) {
                    tableColumn(matcher: matcher)
                    if detailColumnCollapsed {
                        CollapsedPaneStrip(kind: .detail) { setDetailColumnCollapsed(false) }
                    } else {
                        let cap = inspectorCap(available: geo.size.width)
                        ColumnDragHandle(
                            // Reads and writes the width actually shown, so a
                            // drag past the cap can't bank invisible width.
                            width: Binding(
                                get: { min(detailColumnWidth, cap) },
                                set: { detailColumnWidth = min($0, cap) }
                            ),
                            minWidth: Self.minDetailWidth,
                            maxWidth: cap,
                            inverted: true,
                            dividerColor: theme.colors.separator,
                            onCommit: { persistDetailWidth() }
                        )
                        detailColumn(width: min(detailColumnWidth, cap))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.colors.bgContent)
        .overlay(alignment: .bottom) {
            if let intent = dropTracker.intent {
                BranchDropHUD(intent: intent,
                              preview: dropTracker.preview(in: viewModel.history.commits),
                              sourceName: dropTracker.source?.name)
                    .padding(.bottom, Spacing.s16)
                    .transition(.opacity)
            }
        }
        .animation(Motion.fast, value: dropTracker.intent)
        .environment(\.branchDropTracker, dropTracker)
        // The engine spreads lines over the accent's pool; a new accent with a
        // different pool size recolours the graph.
        .task(id: theme.accentSwatch) {
            await viewModel.history.setGraphPaletteSize(LaneColors.pool(accent: theme.accentSwatch).count)
        }
        .navigationTitle("History")
        // New pages bring more of the focused history; a reload may drop it.
        .onChange(of: focusRefreshKey) { refreshFocus() }
        .confirmationDialog(detachedCheckoutTitle,
                            isPresented: detachedCheckoutBinding,
                            titleVisibility: .visible) {
            Button("Checkout (detached)") {
                if let commit = detachedCheckoutTarget {
                    Task { await runCheckoutCommit(commit) }
                }
                detachedCheckoutTarget = nil
            }
            Button("Cancel", role: .cancel) { detachedCheckoutTarget = nil }
        } message: {
            Text("HEAD will detach from any branch. New commits won't belong to a branch — create one first if you plan to keep them.")
        }
        .onChange(of: viewModel.workingCopy.status.isClean) { _, clean in
            // Working tree just went clean (e.g. user committed everything) —
            // the pinned row vanishes from the table, so drop the selection
            // too instead of leaving the detail panel pointing at a row that
            // is no longer visible.
            if clean { isUncommittedSelected = false }
        }
        .modifier(BranchDropDialogs(
            moveRequest: $moveBranchRequest,
            resetRequest: $resetHeadRequest,
            mergeRebaseRequest: $mergeRebaseRequest,
            onMove: { runMove($0) },
            onReset: { runReset($0, mode: $1) },
            onMerge: { runMerge($0) },
            onRebase: { runRebase($0) }
        ))
    }

    private func tableColumn(matcher: ((Commit) -> Bool)?) -> some View {
        ZStack(alignment: .bottom) {
            if viewModel.history.commits.isEmpty && !viewModel.history.hasLoadedLogForCurrentScope {
                HistorySkeleton()
            } else {
                CommitGraphTable(
                    commits: viewModel.history.commits,
                    layouts: viewModel.history.graphLayouts,
                    maxLanes: viewModel.history.graphMaxLanes,
                    refsBySha: viewModel.refsBySha,
                    currentBranch: viewModel.currentBranchName,
                    headSha: viewModel.headSha,
                    selectedSha: viewModel.history.selectedCommitId,
                    workingCopyDirty: !viewModel.workingCopy.status.isClean,
                    uncommittedSelected: isUncommittedSelected,
                    columns: columns,
                    isMatch: matcher,
                    onSelect: { sha in selectCommit(sha) },
                    onUncommittedSelect: { selectUncommitted() },
                    onDoubleClick: { sha in handleDoubleClick(sha) },
                    onAppear: { commit in
                        Task { await viewModel.history.loadMoreIfNeeded(currentItem: commit) }
                    },
                    onBranchDrop: { dropped, context in
                        resolveDrop(dropped, context: context)
                    }
                )
            }
            if viewModel.history.isLoadingMore && !viewModel.history.commits.isEmpty {
                LoadingMoreFooter()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Widest the inspector may be so the table keeps `minTableWidth`
    /// (the handle's own width included).
    private func inspectorCap(available: CGFloat) -> CGFloat {
        let handle = Spacing.s8
        return min(Self.maxDetailWidth, max(Self.minDetailWidth, available - Self.minTableWidth - handle))
    }

    /// Routes the bottom pane between commit-mode and uncommitted-mode so a
    /// single `DiffPane` instance keeps its tokenisation cache across selection
    /// changes within each mode.
    @ViewBuilder
    private var diffPaneContent: some View {
        if isUncommittedSelected {
            DiffPane(
                file: viewModel.workingCopy.selectedWorkingCopyFile?.path,
                status: viewModel.workingCopy.selectedWorkingCopyFile.map { StatusTag.Kind(workingFile: $0.displayStatus) },
                hunks: viewModel.workingCopy.workingCopyDiff,
                loading: viewModel.workingCopy.loadingWorkingCopyDiff,
                emptyState: viewModel.workingCopy.workingCopyDiffEmptyState,
                onClose: { setDiffPaneCollapsed(true) },
                onWhitespaceChange: { Task { await viewModel.workingCopy.reloadSelectedDiff() } },
                hunkActions: viewModel.workingCopy.selectedWorkingCopyFile.flatMap {
                    DiffHunkActions.workingCopy(viewModel, file: $0)
                },
                loadNewSide: viewModel.workingCopy.selectedWorkingCopyFile.map { file -> () async -> [String]? in
                    { await viewModel.workingCopy.newSideLines(for: file) }
                },
                viewMode: diffMode
            )
        } else {
            DiffPane(
                file: viewModel.history.selectedCommitFile,
                status: selectedCommitFileStatus,
                hunks: viewModel.history.commitFileDiff,
                loading: viewModel.history.loadingCommitFileDiff,
                emptyState: viewModel.history.commitFileDiffEmptyState,
                onClose: { setDiffPaneCollapsed(true) },
                onWhitespaceChange: { Task { await viewModel.history.reloadCommitFileDiff() } },
                loadNewSide: commitFileLoader,
                viewMode: diffMode
            )
        }
    }

    /// The selected commit file's content at that commit, for hidden lines.
    private var commitFileLoader: (() async -> [String]?)? {
        guard let sha = viewModel.history.selectedCommit?.sha,
              let path = viewModel.history.selectedCommitFile else { return nil }
        let cli = viewModel.cli
        return { await cli.fileLines(revision: sha, path: path) }
    }

    /// Badge for the commit file in the diff header, once the detail is loaded.
    private var selectedCommitFileStatus: StatusTag.Kind? {
        guard let sha = viewModel.history.selectedCommit?.sha,
              let path = viewModel.history.selectedCommitFile,
              let file = viewModel.history.detailCache[sha]?.files.first(where: { $0.path == path }) else { return nil }
        return StatusTag.Kind(commitFile: file.status)
    }

    /// Inspector: commit (or working-copy) detail over the selected file's
    /// diff, with the same resizable / collapsible diff as before.
    private func detailColumn(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            detailContent
                .frame(maxHeight: .infinity)
            if hasInspectorSelection {
                if diffPaneCollapsed {
                    CollapsedPaneStrip(kind: .diff) { setDiffPaneCollapsed(false) }
                } else {
                    RowDragHandle(
                        height: $diffPaneHeight,
                        minHeight: 36,
                        maxHeight: 800,
                        onCommit: { persistDiffPaneHeight() }
                    )
                    diffPaneContent
                        .frame(height: diffPaneHeight)
                }
            }
        }
        .frame(width: width)
        .background(theme.colors.bgElevated)
    }

    private var hasInspectorSelection: Bool {
        isUncommittedSelected || viewModel.history.selectedCommit != nil
    }

    @ViewBuilder
    private var detailContent: some View {
        if isUncommittedSelected {
            ScrollView {
                UncommittedDetailColumn(
                    viewModel: viewModel,
                    onClose: { setDetailColumnCollapsed(true) }
                )
                .padding(Spacing.s16)
            }
        } else if let commit = viewModel.history.selectedCommit {
            ScrollView {
                CommitDetailColumn(
                    commit: commit,
                    viewModel: viewModel,
                    onClose: { setDetailColumnCollapsed(true) }
                )
                .padding(Spacing.s16)
            }
        } else {
            EmptyState(symbol: "clock.arrow.circlepath", title: String(localized: "Select a commit"),
                       subtitle: String(localized: "Its detail and changes appear here.")) { EmptyView() }
                .overlay(alignment: .topTrailing) {
                    IconButton(symbol: "xmark", accessibilityLabel: String(localized: "Hide commit detail")) {
                        setDetailColumnCollapsed(true)
                    }
                    .help("Hide commit detail")
                    .padding(Spacing.s8)
                }
        }
    }

    // MARK: Selection

    /// Routes a commit-row click through a single funnel so every selection
    /// also lifts the diff pane out of its collapsed / sliver state — clicking
    /// any row should always reveal its diff without a second action.
    private func selectCommit(_ sha: String) {
        if isUncommittedSelected { isUncommittedSelected = false }
        viewModel.history.selectedCommitId = sha
        revealDiffPane()
    }

    /// Counterpart to `selectCommit(_:)` for the pinned "Uncommitted changes"
    /// row. Clears the commit selection so the right detail panel and the
    /// bottom diff pane switch to working-copy mode, picks the first
    /// changed file when nothing is selected yet, and reveals the diff pane.
    private func selectUncommitted() {
        viewModel.history.selectedCommitId = nil
        isUncommittedSelected = true
        if viewModel.workingCopy.selectedWorkingCopyFile == nil {
            let status = viewModel.workingCopy.status
            if let staged = status.stagedFiles.first {
                viewModel.workingCopy.select(staged, side: .staged)
            } else {
                viewModel.workingCopy.select(status.unstagedFiles.first, side: .unstaged)
            }
        }
        revealDiffPane()
    }

    /// Expands the bottom diff pane on every row click — fully collapsed state
    /// gets toggled back open, and a sliver gets bumped up to the default
    /// height so the diff is actually visible.
    private func revealDiffPane() {
        if diffPaneCollapsed {
            setDiffPaneCollapsed(false)
        }
        let revealed = Self.revealedDiffPaneHeight(
            current: diffPaneHeight,
            threshold: Self.collapsedThreshold,
            defaultHeight: Self.defaultDiffHeight
        )
        if revealed != diffPaneHeight {
            withAnimation(Motion.standard) {
                diffPaneHeight = revealed
            }
        }
    }

    /// Pure decision for `revealDiffPane`: a sliver shorter than `threshold`
    /// bumps up to `defaultHeight`; anything taller stays put. Extracted so
    /// the reveal rule is unit-testable without spinning up the view.
    static func revealedDiffPaneHeight(
        current: CGFloat,
        threshold: CGFloat,
        defaultHeight: CGFloat
    ) -> CGFloat {
        current < threshold ? defaultHeight : current
    }

    // MARK: Persistence + collapse helpers

    private func persistDiffPaneHeight() {
        UserDefaults.standard.set(Double(diffPaneHeight), forKey: Self.diffHeightKey)
    }

    private func persistDetailWidth() {
        UserDefaults.standard.set(Double(detailColumnWidth), forKey: Self.detailWidthKey)
    }

    private func setDiffPaneCollapsed(_ collapsed: Bool) {
        withAnimation(Motion.standard) { diffPaneCollapsed = collapsed }
        UserDefaults.standard.set(collapsed, forKey: Self.diffCollapsedKey)
    }

    private func setDetailColumnCollapsed(_ collapsed: Bool) {
        withAnimation(Motion.standard) { detailColumnCollapsed = collapsed }
        UserDefaults.standard.set(collapsed, forKey: Self.detailCollapsedKey)
    }

    // MARK: Search

    /// Closure passed to the table — `nil` when search is empty so every row
    /// renders at full opacity. `body` evaluates this once per render and
    /// reuses it for both the match-count badge and the table's dim filter.
    private var searchMatcher: ((Commit) -> Bool)? {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return nil }
        // Case-insensitive search instead of `lowercased()` per field: this
        // runs over the whole log for the match count and per visible row on
        // every render, and each `lowercased()` allocated a new string.
        // Shas are already lowercase hex.
        return { commit in
            commit.subject.range(of: query, options: .caseInsensitive) != nil
                || commit.authorName.range(of: query, options: .caseInsensitive) != nil
                || commit.authorEmail.range(of: query, options: .caseInsensitive) != nil
                || commit.sha.hasPrefix(query)
        }
    }

    // MARK: Focus

    /// Search and focus together: a row is bright only if it passes both.
    private var combinedMatcher: ((Commit) -> Bool)? {
        let search = searchMatcher
        guard let members = focus?.members else { return search }
        return { commit in members.contains(commit.sha) && (search?(commit) ?? true) }
    }

    private func toggleFocus() {
        if focus != nil {
            focus = nil
        } else if let commit = viewModel.history.selectedCommit {
            focus = HistoryFocus(sha: commit.sha, label: focusLabel(for: commit), members: [])
            refreshFocus()
        }
    }

    private func toggleRemoteBranches() {
        let history = viewModel.history
        let on = !history.showsRemoteBranches
        Task { await history.setShowsRemoteBranches(on) }
    }

    private func refreshFocus() {
        guard let current = focus else { return }
        let members = CommitAncestry.reachable(from: current.sha, in: viewModel.history.commits)
        focus = members.isEmpty ? nil : HistoryFocus(sha: current.sha, label: current.label, members: members)
    }

    private var focusRefreshKey: String {
        "\(viewModel.history.commits.count)|\(viewModel.history.commits.first?.sha ?? "")"
    }

    /// The local branch at the commit (the current one first), else its SHA.
    private func focusLabel(for commit: Commit) -> String {
        let locals = (viewModel.refsBySha[commit.sha] ?? []).filter(\.isLocalBranch)
        let current = locals.first { $0.name == viewModel.currentBranchName }
        return (current ?? locals.first)?.displayName ?? commit.shortSha
    }

    private var detachedCheckoutBinding: Binding<Bool> {
        Binding(get: { detachedCheckoutTarget != nil },
                set: { if !$0 { detachedCheckoutTarget = nil } })
    }

    private var detachedCheckoutTitle: String {
        guard let commit = detachedCheckoutTarget else { return "" }
        let shortSha = commit.shortSha
        return String(localized: "Checkout \(shortSha)?")
    }
}

/// The commit History is focused on and its loaded history.
private struct HistoryFocus: Equatable {
    let sha: String
    let label: String
    let members: Set<String>
}

#Preview("Loaded") {
    @Previewable @State var theme = AppTheme()
    HistoryView(viewModel: .preview)
        .previewAppState(.preview)
        .frame(width: 1200, height: 720)
        .appTheme(theme)
}

#Preview("Loading initial") {
    @Previewable @State var theme = AppTheme()
    let vm: RepositoryViewModel = {
        let v = RepositoryViewModel.preview
        v.history.commits = []
        v.history.isLoadingInitial = true
        return v
    }()
    HistoryView(viewModel: vm)
        .previewAppState(.preview)
        .frame(width: 1200, height: 720)
        .appTheme(theme)
}
