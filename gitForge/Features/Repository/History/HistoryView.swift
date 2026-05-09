import SwiftUI

/// Top-level History pane: graph + diff pane on the left, commit detail on
/// the right. Owns the resizable layout state (panel widths / collapsed
/// flags / column widths) and routes drag-drop / double-click events into
/// the right confirmation dialogs (action runners live in
/// `HistoryView+Actions.swift`).
struct HistoryView: View {
    @Bindable var viewModel: RepositoryViewModel
    @Environment(\.appTheme) var theme
    @Environment(AppState.self) var appState

    @State var search: String = ""
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
    /// the pane reads `theme.defaultDiffMode` so changes in Settings show up
    /// immediately and re-entering History always lands on the default.
    @State private var diffModeOverride: DiffPane.ViewMode?

    @State private var columns = ResizableTableModel(
        id: "history",
        columns: [
            (id: "graph",     defaultWidth: 110, minWidth: 80),
            (id: "branchTag", defaultWidth: 220, minWidth: 80),
            (id: "message",   defaultWidth: 480, minWidth: 240),
            (id: "author",    defaultWidth: 130, minWidth: 80),
            (id: "sha",       defaultWidth: 80,  minWidth: 60),
            (id: "when",      defaultWidth: 70,  minWidth: 50),
        ]
    )

    private static let diffHeightKey = "gitForge.history.diffPaneHeight"
    private static let detailWidthKey = "gitForge.history.detailPanelWidth"
    private static let diffCollapsedKey = "gitForge.history.diffPaneCollapsed"
    private static let detailCollapsedKey = "gitForge.history.detailPanelCollapsed"
    private static let collapsedThreshold: CGFloat = 80
    private static let defaultDiffHeight: CGFloat = 280
    private static let minDetailWidth: CGFloat = 280
    private static let maxDetailWidth: CGFloat = 600

    @State private var diffPaneHeightValue: CGFloat = {
        let stored = UserDefaults.standard.double(forKey: HistoryView.diffHeightKey)
        return stored > 0 ? CGFloat(stored) : 280
    }()

    @State private var detailColumnWidth: CGFloat = {
        let stored = UserDefaults.standard.double(forKey: HistoryView.detailWidthKey)
        let resolved = stored > 0 ? CGFloat(stored) : DesignTokens.Detail.panelWidth
        return min(max(HistoryView.minDetailWidth, resolved), HistoryView.maxDetailWidth)
    }()

    @State private var diffPaneCollapsed: Bool = UserDefaults.standard.bool(forKey: HistoryView.diffCollapsedKey)
    @State private var detailColumnCollapsed: Bool = UserDefaults.standard.bool(forKey: HistoryView.detailCollapsedKey)

    private var diffPaneHeight: Binding<CGFloat> {
        Binding(get: { diffPaneHeightValue }, set: { diffPaneHeightValue = $0 })
    }

    private var diffMode: Binding<DiffPane.ViewMode> {
        Binding(
            get: { diffModeOverride ?? theme.defaultDiffMode },
            set: { diffModeOverride = $0 }
        )
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.none) {
            ContentHeader(title: "History") {
                MonoText("\(viewModel.currentBranchName ?? "—") · \(viewModel.commits.count) commits", dim: true)
            } right: {
                HistoryToolbar(viewModel: viewModel)
            }
            HistoryFiltersBar(
                search: $search,
                totalCount: viewModel.commits.count,
                matchCount: matchCount
            )
            HStack(spacing: DesignTokens.Spacing.none) {
                graphAndDiffColumn
                if detailColumnCollapsed {
                    CollapsedPaneStrip(kind: .detail) { setDetailColumnCollapsed(false) }
                } else {
                    ColumnDragHandle(
                        width: $detailColumnWidth,
                        minWidth: Self.minDetailWidth,
                        maxWidth: Self.maxDetailWidth,
                        inverted: true,
                        dividerColor: theme.palette.lineStrong,
                        onCommit: { persistDetailWidth() }
                    )
                    detailColumn
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.bg2)
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

    private var graphAndDiffColumn: some View {
        VStack(spacing: DesignTokens.Spacing.none) {
            ZStack(alignment: .bottom) {
                if viewModel.commits.isEmpty && !viewModel.hasLoadedLogForCurrentScope {
                    HistorySkeleton()
                } else {
                    CommitGraphTable(
                        commits: viewModel.commits,
                        layouts: viewModel.graphLayouts,
                        refsBySha: viewModel.refsBySha,
                        currentBranch: viewModel.currentBranchName,
                        selectedSha: viewModel.selectedCommitId,
                        workingCopyDirty: !viewModel.status.isClean,
                        columns: columns,
                        isMatch: searchMatcher,
                        onSelect: { sha in viewModel.selectedCommitId = sha },
                        onDoubleClick: { sha in handleDoubleClick(sha) },
                        onAppear: { commit in
                            Task { await viewModel.loadMoreIfNeeded(currentItem: commit) }
                        },
                        onBranchDrop: { dropped, context in
                            resolveDrop(dropped, context: context)
                        }
                    )
                }
                if viewModel.isLoadingMore && !viewModel.commits.isEmpty {
                    LoadingMoreFooter()
                }
            }
            .frame(maxHeight: .infinity)
            if diffPaneCollapsed {
                CollapsedPaneStrip(kind: .diff) { setDiffPaneCollapsed(false) }
            } else {
                RowDragHandle(
                    height: diffPaneHeight,
                    minHeight: 36,
                    maxHeight: 800,
                    onCommit: { persistDiffPaneHeight() }
                )
                DiffPane(
                    file: viewModel.selectedCommitFile,
                    hunks: viewModel.commitFileDiff,
                    loading: viewModel.loadingCommitFileDiff,
                    emptyState: viewModel.commitFileDiffEmptyState,
                    onClose: { setDiffPaneCollapsed(true) },
                    viewMode: diffMode
                )
                .frame(height: diffPaneHeight.wrappedValue)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: viewModel.selectedCommitFile) { _, newFile in
            // Auto-expand when a file is selected and the diff pane has been
            // shrunk to a sliver — a fully collapsed pane stays put.
            guard newFile != nil, !diffPaneCollapsed,
                  diffPaneHeight.wrappedValue < Self.collapsedThreshold else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                diffPaneHeight.wrappedValue = Self.defaultDiffHeight
            }
        }
    }

    private var detailColumn: some View {
        Group {
            if let commit = viewModel.selectedCommit {
                ScrollView {
                    CommitDetailColumn(
                        commit: commit,
                        viewModel: viewModel,
                        onClose: { setDetailColumnCollapsed(true) }
                    )
                    .padding(DesignTokens.Spacing.xxxxl)
                }
            } else {
                EmptyState(icon: .diamond, title: "Select a commit",
                           subtitle: "Detail appears here.") { EmptyView() }
                    .overlay(alignment: .topTrailing) {
                        IconButton(.x, accessibilityLabel: "Hide commit detail") {
                            setDetailColumnCollapsed(true)
                        }
                        .help("Hide commit detail")
                        .padding(DesignTokens.Spacing.md)
                    }
            }
        }
        .frame(width: detailColumnWidth)
        .background(theme.palette.bg1)
    }

    // MARK: Persistence + collapse helpers

    private func persistDiffPaneHeight() {
        UserDefaults.standard.set(Double(diffPaneHeightValue), forKey: Self.diffHeightKey)
    }

    private func persistDetailWidth() {
        UserDefaults.standard.set(Double(detailColumnWidth), forKey: Self.detailWidthKey)
    }

    private func setDiffPaneCollapsed(_ collapsed: Bool) {
        withAnimation(.easeOut(duration: 0.18)) { diffPaneCollapsed = collapsed }
        UserDefaults.standard.set(collapsed, forKey: Self.diffCollapsedKey)
    }

    private func setDetailColumnCollapsed(_ collapsed: Bool) {
        withAnimation(.easeOut(duration: 0.18)) { detailColumnCollapsed = collapsed }
        UserDefaults.standard.set(collapsed, forKey: Self.detailCollapsedKey)
    }

    // MARK: Search

    private var trimmedQuery: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchCount: Int {
        guard !trimmedQuery.isEmpty else { return viewModel.commits.count }
        return viewModel.commits.lazy.filter { commitMatches($0, query: trimmedQuery) }.count
    }

    private func commitMatches(_ commit: Commit, query: String) -> Bool {
        let q = query.lowercased()
        return commit.subject.lowercased().contains(q)
            || commit.authorName.lowercased().contains(q)
            || commit.authorEmail.lowercased().contains(q)
            || commit.sha.lowercased().hasPrefix(q)
    }

    /// Closure passed to the table — `nil` when search is empty so every row
    /// renders at full opacity.
    private var searchMatcher: ((Commit) -> Bool)? {
        let query = trimmedQuery
        guard !query.isEmpty else { return nil }
        return { commitMatches($0, query: query) }
    }

    private var detachedCheckoutBinding: Binding<Bool> {
        Binding(get: { detachedCheckoutTarget != nil },
                set: { if !$0 { detachedCheckoutTarget = nil } })
    }

    private var detachedCheckoutTitle: String {
        guard let commit = detachedCheckoutTarget else { return "" }
        return "Checkout \(commit.shortSha)?"
    }
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
        v.commits = []
        v.isLoadingInitial = true
        return v
    }()
    HistoryView(viewModel: vm)
        .previewAppState(.preview)
        .frame(width: 1200, height: 720)
        .appTheme(theme)
}
