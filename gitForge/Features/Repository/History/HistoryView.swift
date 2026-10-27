import SwiftUI

/// Top-level History pane: the commit table on the left, the inspector
/// (commit detail over the selected file's diff) on the right (redesign
/// spec §6.2), or the diff alone when expanded. The split and the
/// inspector own their sizes (`HistorySplitLayout`, `HistoryInspector`);
/// this view owns the selection, search and focus, the table's column
/// widths, whether the inspector shows (toolbar button and View › Show
/// Inspector, ⌃⌘I), and routes drag-drop / double-click events into the
/// right confirmation dialogs (action runners live in `HistoryView+Actions.swift`).
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
    /// The diff fills the pane instead of sitting under the detail.
    @State private var isDiffExpanded = false
    /// The inspector shows next to the table (persisted).
    @State private var isInspectorVisible = HistorySplitMetrics.storedInspectorVisible()
    /// Drop target under a dragged branch chip, shown in the intent HUD.
    @State var dropTracker = BranchDropTracker()

    @State private var columns = ResizableTableModel.historyColumns()

    private var diffMode: Binding<DiffPane.ViewMode> {
        Binding(
            get: { diffModeOverride ?? preferences.defaultDiffMode },
            set: { diffModeOverride = $0 }
        )
    }

    var body: some View {
        Group {
            if isDiffExpanded {
                HistoryExpandedDiff(
                    viewModel: viewModel,
                    isUncommittedSelected: isUncommittedSelected,
                    diffMode: diffMode,
                    onExit: { setDiffExpanded(false) }
                )
            } else {
                browser
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) { inspectorToggle }
        }
        // View › Show Inspector (⌃⌘I); off while the diff fills the pane.
        .focusedSceneValue(\.historyInspectorVisible,
                           isDiffExpanded ? nil : $isInspectorVisible.animation(Motion.standard))
        .onChange(of: isInspectorVisible) { _, visible in
            HistorySplitMetrics.storeInspectorVisible(visible)
        }
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
        // Nothing left to show expanded (the selection went away).
        .onChange(of: hasSelection) { _, has in
            if !has { isDiffExpanded = false }
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

    /// Filters over the table and the inspector.
    private var browser: some View {
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
            HistorySplitLayout(table: tableColumn(matcher: matcher), isInspectorVisible: $isInspectorVisible) {
                HistoryInspector(
                    viewModel: viewModel,
                    isUncommittedSelected: isUncommittedSelected,
                    diffMode: diffMode,
                    onExpandDiff: { setDiffExpanded(true) }
                )
            }
        }
    }

    /// Shows or hides the inspector, icon only so it fits the toolbar at the
    /// window's minimum width.
    private var inspectorToggle: some View {
        let title = isInspectorVisible ? String(localized: "Hide Inspector") : String(localized: "Show Inspector")
        return Button {
            withAnimation(Motion.standard) { isInspectorVisible.toggle() }
        } label: {
            Label(title, systemImage: "sidebar.trailing")
        }
        .labelStyle(.iconOnly)
        .help(Text(verbatim: "\(title) (⌃⌘I)"))
        .disabled(isDiffExpanded)
    }

    private func tableColumn(matcher: ((Commit) -> Bool)?) -> some View {
        ZStack(alignment: .bottom) {
            if viewModel.history.commits.isEmpty && !viewModel.history.hasLoadedLogForCurrentScope {
                HistorySkeleton()
            } else {
                CommitGraphTable(
                    commits: viewModel.history.commits,
                    logRevision: viewModel.history.logRevision,
                    layouts: viewModel.history.graphLayouts,
                    maxLanes: viewModel.history.graphMaxLanes,
                    refChips: viewModel.history.refChips,
                    currentBranch: viewModel.currentBranchName,
                    headSha: viewModel.headSha,
                    selectedSha: viewModel.history.selectedCommitId,
                    showsUncommittedRow: viewModel.history.showsUncommittedRow,
                    uncommittedStep: viewModel.history.uncommittedStep,
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

    // MARK: Selection

    /// Routes a commit-row click through a single funnel, leaving the
    /// "Uncommitted changes" selection. The inspector reveals the diff.
    private func selectCommit(_ sha: String) {
        if isUncommittedSelected { isUncommittedSelected = false }
        viewModel.history.selectedCommitId = sha
    }

    /// Counterpart to `selectCommit(_:)` for the pinned "Uncommitted changes"
    /// row. Clears the commit selection so the right detail panel and the
    /// bottom diff pane switch to working-copy mode, and picks the first
    /// changed file when nothing is selected yet.
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
    }

    private var hasSelection: Bool {
        isUncommittedSelected || viewModel.history.selectedCommit != nil
    }

    private func setDiffExpanded(_ expanded: Bool) {
        guard !expanded || hasSelection else { return }
        withAnimation(Motion.fast) { isDiffExpanded = expanded }
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

extension FocusedValues {
    /// Whether History's inspector shows, while History is on screen with
    /// the inspector next to the table (`ViewCommands`' Show Inspector).
    @Entry var historyInspectorVisible: Binding<Bool>?
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
