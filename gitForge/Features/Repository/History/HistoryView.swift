import SwiftUI

/// `.gf-view-history` — orchestrates graph table + diff pane + commit detail.
struct HistoryView: View {
    /// "Move local branch X to commit Y" — fired when a non-current branch
    /// chip is dropped on another commit row.
    struct MoveBranchRequest: Identifiable, Equatable {
        let id = UUID()
        let branch: GitRef
        let targetSha: String
        let targetShortSha: String
    }

    /// "Reset HEAD to commit Y" — fired when the current branch chip is dropped
    /// on another commit row. The dialog asks for a reset mode (soft/mixed/hard).
    struct ResetHeadRequest: Identifiable, Equatable {
        let id = UUID()
        let branchName: String
        let targetSha: String
        let targetShortSha: String
    }

    /// "Merge X into Y or rebase Y onto X" — fired when a chip is dropped on
    /// another local-branch chip. The dialog offers both options plus cancel.
    struct MergeRebaseRequest: Identifiable, Equatable {
        let id = UUID()
        let source: GitRef
        let target: GitRef
    }

    @Bindable var viewModel: RepositoryViewModel
    @Environment(\.appTheme) private var theme
    @Environment(AppState.self) private var appState

    @State private var search: String = ""
    /// Set when the user double-clicks a commit that no local branch points at.
    /// Drives the "checkout will be detached" confirmation dialog.
    @State private var detachedCheckoutTarget: Commit?
    /// Drag-and-drop pending actions — one of these is set when a `BranchChip`
    /// is dropped on a row or another chip. Each drives its own confirmation
    /// dialog. Only one is set at a time per drop.
    @State private var moveBranchRequest: MoveBranchRequest?
    @State private var resetHeadRequest: ResetHeadRequest?
    @State private var mergeRebaseRequest: MergeRebaseRequest?
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
    private static let collapsedThreshold: CGFloat = 80
    private static let defaultDiffHeight: CGFloat = 280

    private static let detailWidthKey = "gitForge.history.detailPanelWidth"
    private static let minDetailWidth: CGFloat = 280
    private static let maxDetailWidth: CGFloat = 600

    private static let diffCollapsedKey = "gitForge.history.diffPaneCollapsed"
    private static let detailCollapsedKey = "gitForge.history.detailPanelCollapsed"
    private static let collapsedStripWidth: CGFloat = 32
    private static let collapsedStripHeight: CGFloat = 30

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
        Binding(
            get: { diffPaneHeightValue },
            set: { diffPaneHeightValue = $0 }
        )
    }

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
                ToolButton(
                    .fetch,
                    label: "Fetch",
                    disabled: viewModel.remoteOperation != nil && viewModel.remoteOperation != .fetching,
                    loading: viewModel.remoteOperation == .fetching
                ) {
                    Task { await viewModel.fetch() }
                }
                pullSplitButton
                pushSplitButton
            }
            filtersBar
            HStack(spacing: DesignTokens.Spacing.none) {
                graphAndDiffColumn
                if detailColumnCollapsed {
                    detailColumnCollapsedStrip
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

    /// Resolve a drop event into the right confirmation dialog. Three branches:
    /// - Drop on a chip → merge / rebase between two local branches.
    /// - Drop of HEAD on a commit → reset (mode picker).
    /// - Drop of any other local branch on a commit → move (`branch -f`).
    /// Anything that can't be resolved (orphan refs, drops where source ==
    /// target, drops on non-local target chips) falls through silently.
    private func handleBranchDrop(dropped: DraggedBranch, context: BranchDropContext) {
        guard let source = viewModel.refs.first(where: { $0.isLocalBranch && $0.name == dropped.name })
        else { return }

        switch context {
        case .onCommit(let targetSha):
            guard targetSha != dropped.sourceSha else { return }
            let shortSha = String(targetSha.prefix(7))
            if dropped.isCurrent {
                resetHeadRequest = ResetHeadRequest(
                    branchName: dropped.name,
                    targetSha: targetSha,
                    targetShortSha: shortSha
                )
            } else {
                moveBranchRequest = MoveBranchRequest(
                    branch: source,
                    targetSha: targetSha,
                    targetShortSha: shortSha
                )
            }

        case .onBranch(let targetBranchName, _):
            guard targetBranchName != dropped.name else { return }
            guard let target = viewModel.refs.first(where: {
                $0.isLocalBranch && $0.name == targetBranchName
            }) else { return }
            mergeRebaseRequest = MergeRebaseRequest(source: source, target: target)
        }
    }

    private var detachedCheckoutBinding: Binding<Bool> {
        Binding(get: { detachedCheckoutTarget != nil },
                set: { if !$0 { detachedCheckoutTarget = nil } })
    }

    private var detachedCheckoutTitle: String {
        guard let commit = detachedCheckoutTarget else { return "" }
        return "Checkout \(commit.shortSha)?"
    }

    /// Resolve the double-click target. If a local branch points at the commit
    /// (and it's not already current), check that branch out — safer than a
    /// detached HEAD on the same SHA. Otherwise prompt for confirmation before
    /// detaching.
    private func handleCommitDoubleClick(_ sha: String) {
        guard let commit = viewModel.commits.first(where: { $0.sha == sha }) else { return }
        let candidates = (refsBySha[sha] ?? []).filter { ref in
            ref.isLocalBranch && ref.name != viewModel.currentBranchName
        }
        if let local = candidates.first {
            Task { await runCheckoutBranch(local) }
            return
        }
        // Already on a branch that points here — no-op.
        if (refsBySha[sha] ?? []).contains(where: {
            $0.isLocalBranch && $0.name == viewModel.currentBranchName
        }) {
            appState.activeToast = ToastMessage(message: "Already on \(viewModel.currentBranchName ?? commit.shortSha)", kind: .ok)
            return
        }
        detachedCheckoutTarget = commit
    }

    private func runCheckoutBranch(_ ref: GitRef) async {
        switch await viewModel.checkoutBranch(ref) {
        case .success:
            appState.activeToast = ToastMessage(message: "Checked out \(ref.displayName)", kind: .ok)
        case .failure(let err):
            appState.activeToast = ToastMessage(
                message: (err as? LocalizedError)?.errorDescription ?? err.localizedDescription,
                kind: .error)
        }
    }

    private func runCheckoutCommit(_ commit: Commit) async {
        switch await viewModel.checkoutCommit(commit.sha) {
        case .success:
            appState.activeToast = ToastMessage(message: "Detached HEAD at \(commit.shortSha)", kind: .ok)
        case .failure(let err):
            appState.activeToast = ToastMessage(
                message: (err as? LocalizedError)?.errorDescription ?? err.localizedDescription,
                kind: .error)
        }
    }

    // MARK: Drag-and-drop runners

    private func runMove(_ request: MoveBranchRequest) {
        Task {
            switch await viewModel.moveBranch(request.branch, to: request.targetSha) {
            case .success:
                appState.activeToast = ToastMessage(
                    message: "Moved \(request.branch.displayName) to \(request.targetShortSha)",
                    kind: .ok)
            case .failure(let err):
                appState.activeToast = ToastMessage(
                    message: (err as? LocalizedError)?.errorDescription ?? err.localizedDescription,
                    kind: .error)
            }
        }
    }

    private func runReset(_ request: ResetHeadRequest, mode: GitCLI.ResetMode) {
        Task {
            let outcome = await viewModel.reset(to: request.targetSha, mode: mode)
            reportIntegration(
                outcome,
                success: "Reset \(request.branchName) to \(request.targetShortSha) (\(mode.rawValue))",
                conflicts: "Reset paused on conflicts — resolve to continue"
            )
        }
    }

    private func runMerge(_ request: MergeRebaseRequest) {
        Task {
            let outcome = await viewModel.mergeBranch(source: request.source, into: request.target)
            reportIntegration(
                outcome,
                success: "Merged \(request.source.displayName) into \(request.target.displayName)",
                conflicts: "Merge has conflicts — resolve to continue"
            )
        }
    }

    private func runRebase(_ request: MergeRebaseRequest) {
        Task {
            // Drop semantics: dragging X onto Y rebases X onto Y (X gets
            // replayed on top of Y). `rebaseOnto` rebases the CURRENT branch,
            // so we have to be on `source` first.
            if request.source.name != viewModel.currentBranchName {
                if case .failure(let err) = await viewModel.checkoutBranch(request.source) {
                    appState.activeToast = ToastMessage(
                        message: (err as? LocalizedError)?.errorDescription ?? err.localizedDescription,
                        kind: .error)
                    return
                }
            }
            let outcome = await viewModel.rebaseOnto(request.target)
            reportIntegration(
                outcome,
                success: "Rebased \(request.source.displayName) onto \(request.target.displayName)",
                conflicts: "Rebase has conflicts — resolve to continue"
            )
        }
    }

    private func reportIntegration(_ outcome: RepositoryViewModel.IntegrationOutcome,
                                   success: String,
                                   conflicts: String) {
        switch outcome {
        case .clean:
            appState.activeToast = ToastMessage(message: success, kind: .ok)
        case .conflicts:
            appState.workspaceSection = .conflict
            appState.activeToast = ToastMessage(message: conflicts, kind: .warn)
        case .failed(let message):
            appState.activeToast = ToastMessage(message: message, kind: .error)
        }
    }

    private var filtersBar: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            GFTextField(placeholder: "Search subject, author, sha…", text: $search)
                .frame(maxWidth: 320)
            Spacer()
            MonoText(matchSummary, dim: true)
        }
        .padding(.horizontal, DesignTokens.Spacing.xxxxl)
        .padding(.vertical, DesignTokens.Spacing.md)
        .background(theme.palette.bg2)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line).frame(height: DesignTokens.Stroke.regular) }
    }

    private var refsBySha: [String: [GitRef]] {
        Dictionary(grouping: viewModel.refs) { $0.targetSha }
    }

    private var trimmedQuery: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchSummary: String {
        guard !trimmedQuery.isEmpty else { return "\(viewModel.commits.count) commits" }
        let count = viewModel.commits.lazy.filter { commitMatches($0, query: trimmedQuery) }.count
        return "\(count) of \(viewModel.commits.count) match"
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

    @ViewBuilder
    private var pullSplitButton: some View {
        SplitToolButton(
            kind: .pull,
            label: "Pull",
            badge: viewModel.behindCount,
            primary: false,
            loading: viewModel.remoteOperation == .pulling,
            disabled: viewModel.remoteOperation != nil && viewModel.remoteOperation != .pulling,
            action: { Task { await viewModel.pull() } }
        ) {
            Button("Pull (only if no merge needed)") {
                Task { await viewModel.pull(ffOnly: true) }
            }
            Button("Pull and rebase my commits") {
                Task { await viewModel.pull(rebase: true) }
            }
        }
    }

    @ViewBuilder
    private var pushSplitButton: some View {
        SplitToolButton(
            kind: .push,
            label: "Push",
            badge: viewModel.aheadCount,
            primary: true,
            loading: viewModel.remoteOperation == .pushing,
            disabled: viewModel.remoteOperation != nil && viewModel.remoteOperation != .pushing,
            action: { Task { await viewModel.push() } }
        ) {
            Button("Force push (only if remote unchanged)", role: .destructive) {
                Task { await viewModel.push(forceWithLease: true) }
            }
        }
    }

    private var graphAndDiffColumn: some View {
        VStack(spacing: DesignTokens.Spacing.none) {
            ZStack(alignment: .bottom) {
                if viewModel.commits.isEmpty && !viewModel.hasLoadedLogForCurrentScope {
                    commitLogSkeleton
                } else {
                    CommitGraphTable(
                        commits: viewModel.commits,
                        layouts: viewModel.graphLayouts,
                        refsBySha: refsBySha,
                        currentBranch: viewModel.currentBranchName,
                        selectedSha: viewModel.selectedCommitId,
                        workingCopyDirty: !viewModel.status.isClean,
                        columns: columns,
                        isMatch: searchMatcher,
                        onSelect: { sha in viewModel.selectedCommitId = sha },
                        onDoubleClick: { sha in handleCommitDoubleClick(sha) },
                        onAppear: { commit in
                            Task { await viewModel.loadMoreIfNeeded(currentItem: commit) }
                        },
                        onBranchDrop: { dropped, context in
                            handleBranchDrop(dropped: dropped, context: context)
                        }
                    )
                }

                if viewModel.isLoadingMore && !viewModel.commits.isEmpty {
                    loadingMoreFooter
                }
            }
            .frame(maxHeight: .infinity)
            if diffPaneCollapsed {
                diffPaneCollapsedStrip
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
            guard newFile != nil, !diffPaneCollapsed,
                  diffPaneHeight.wrappedValue < Self.collapsedThreshold else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                diffPaneHeight.wrappedValue = Self.defaultDiffHeight
            }
        }
    }

    private var diffPaneCollapsedStrip: some View {
        Button {
            setDiffPaneCollapsed(false)
        } label: {
            HStack(spacing: DesignTokens.Spacing.md) {
                GFIcon(kind: .diff, size: 12, stroke: theme.palette.fg2)
                Text("Show diff pane")
                    .font(AppFont.sans(12))
                    .foregroundStyle(theme.palette.fg2)
                Spacer(minLength: 0)
                GFIcon(kind: .arrowU, size: 11, stroke: theme.palette.fg3)
            }
            .padding(.horizontal, DesignTokens.Spacing.xxl)
            .frame(height: Self.collapsedStripHeight)
            .frame(maxWidth: .infinity)
            .background(theme.palette.bg1)
            .overlay(alignment: .top) { Rectangle().fill(theme.palette.lineStrong).frame(height: DesignTokens.Stroke.regular) }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Show the diff pane")
    }

    // MARK: Loading placeholders

    private static let placeholderSubjects = [
        "feat: add merge request integration",
        "fix: handle nil reviewer avatar URLs",
        "refactor: split provider-specific mappers",
        "chore: bump dependency versions",
        "feat: skeleton loaders for first-fetch states",
        "test: cover empty merge request payloads",
        "fix: history scroll jumps on selection",
        "feat: graph perf improvements",
    ]

    private var commitLogSkeleton: some View {
        ScrollView {
            LazyVStack(spacing: DesignTokens.Spacing.none) {
                ForEach(0..<10, id: \.self) { index in
                    commitPlaceholderRow(index: index)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.palette.bg2)
        .skeleton(true)
    }

    @ViewBuilder
    private func commitPlaceholderRow(index: Int) -> some View {
        let subject = Self.placeholderSubjects[index % Self.placeholderSubjects.count]
        HStack(spacing: DesignTokens.Spacing.xl) {
            // branch/tag column
            Text("main")
                .font(AppFont.mono(11, family: theme.monoFont))
                .padding(.horizontal, DesignTokens.Spacing.sm).padding(.vertical, DesignTokens.Spacing.hairline)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).fill(theme.palette.bg3))
                .frame(width: 100, alignment: .leading)
            // message column
            Text(subject)
                .font(AppFont.sans(12.5))
                .foregroundStyle(theme.palette.fg1)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            // author column
            Text("9alvaro0")
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
                .frame(width: 110, alignment: .leading)
            // sha column
            Text("abc1234")
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.accent)
                .frame(width: 70, alignment: .leading)
            // when column
            Text("2h")
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
                .frame(width: 50, alignment: .leading)
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .frame(height: DesignTokens.Control.height)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line).frame(height: DesignTokens.Stroke.regular) }
    }

    private var loadingMoreFooter: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            ProgressView().controlSize(.small).scaleEffect(0.7)
            Text("Loading more commits…")
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
        }
        .padding(.horizontal, DesignTokens.Spacing.xxl)
        .padding(.vertical, DesignTokens.Spacing.md)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
        .padding(.bottom, DesignTokens.Spacing.xl)
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
                        IconButton(.x) { setDetailColumnCollapsed(true) }
                            .help("Hide commit detail")
                            .padding(DesignTokens.Spacing.md)
                    }
            }
        }
        .frame(width: detailColumnWidth)
        .background(theme.palette.bg1)
    }

    private var detailColumnCollapsedStrip: some View {
        Button {
            setDetailColumnCollapsed(false)
        } label: {
            VStack(spacing: DesignTokens.Spacing.none) {
                GFIcon(kind: .diamond, size: 13, stroke: theme.palette.fg2)
                    .padding(.top, DesignTokens.Spacing.xxl)
                Spacer(minLength: 0)
            }
            .frame(width: Self.collapsedStripWidth)
            .frame(maxHeight: .infinity)
            .background(theme.palette.bg1)
            .overlay(alignment: .leading) { Rectangle().fill(theme.palette.lineStrong).frame(width: DesignTokens.Stroke.regular) }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Show commit detail")
    }
}

/// Hosts the three confirmation dialogs that arm when a `BranchChip` is
/// dropped on a commit row or another chip. Extracted from the main view
/// because chaining three more `confirmationDialog` modifiers on top of
/// `HistoryView`'s body was tipping the type-checker into timeouts on debug
/// builds (see `feedback_swiftui_typecheck.md`).
private struct BranchDropDialogs: ViewModifier {
    @Binding var moveRequest: HistoryView.MoveBranchRequest?
    @Binding var resetRequest: HistoryView.ResetHeadRequest?
    @Binding var mergeRebaseRequest: HistoryView.MergeRebaseRequest?
    let onMove: (HistoryView.MoveBranchRequest) -> Void
    let onReset: (HistoryView.ResetHeadRequest, GitCLI.ResetMode) -> Void
    let onMerge: (HistoryView.MergeRebaseRequest) -> Void
    let onRebase: (HistoryView.MergeRebaseRequest) -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                moveTitle,
                isPresented: moveBinding,
                titleVisibility: .visible
            ) {
                Button("Move") {
                    if let r = moveRequest { onMove(r) }
                    moveRequest = nil
                }
                Button("Cancel", role: .cancel) { moveRequest = nil }
            } message: {
                Text("Force-updates the local branch (`git branch -f`). Existing commits aren't lost — they'll just no longer be reachable from this branch.")
            }
            .confirmationDialog(
                resetTitle,
                isPresented: resetBinding,
                titleVisibility: .visible
            ) {
                Button("Soft (keep changes staged)") {
                    if let r = resetRequest { onReset(r, .soft) }
                    resetRequest = nil
                }
                Button("Mixed (keep changes unstaged)") {
                    if let r = resetRequest { onReset(r, .mixed) }
                    resetRequest = nil
                }
                Button("Hard (discard everything)", role: .destructive) {
                    if let r = resetRequest { onReset(r, .hard) }
                    resetRequest = nil
                }
                Button("Cancel", role: .cancel) { resetRequest = nil }
            } message: {
                Text("Moves \(resetRequest?.branchName ?? "HEAD") and HEAD. Hard discards uncommitted work in the worktree.")
            }
            .confirmationDialog(
                mergeRebaseTitle,
                isPresented: mergeRebaseBinding,
                titleVisibility: .visible
            ) {
                Button("Merge \(mergeRebaseRequest?.source.displayName ?? "") into \(mergeRebaseRequest?.target.displayName ?? "")") {
                    if let r = mergeRebaseRequest { onMerge(r) }
                    mergeRebaseRequest = nil
                }
                Button("Rebase \(mergeRebaseRequest?.source.displayName ?? "") onto \(mergeRebaseRequest?.target.displayName ?? "")") {
                    if let r = mergeRebaseRequest { onRebase(r) }
                    mergeRebaseRequest = nil
                }
                Button("Cancel", role: .cancel) { mergeRebaseRequest = nil }
            } message: {
                Text(mergeRebaseMessage)
            }
    }

    private var moveBinding: Binding<Bool> {
        Binding(get: { moveRequest != nil }, set: { if !$0 { moveRequest = nil } })
    }
    private var resetBinding: Binding<Bool> {
        Binding(get: { resetRequest != nil }, set: { if !$0 { resetRequest = nil } })
    }
    private var mergeRebaseBinding: Binding<Bool> {
        Binding(get: { mergeRebaseRequest != nil }, set: { if !$0 { mergeRebaseRequest = nil } })
    }

    private var moveTitle: String {
        guard let r = moveRequest else { return "" }
        return "Move \(r.branch.displayName) to \(r.targetShortSha)?"
    }

    private var resetTitle: String {
        guard let r = resetRequest else { return "" }
        return "Reset \(r.branchName) to \(r.targetShortSha)?"
    }

    private var mergeRebaseTitle: String {
        guard let r = mergeRebaseRequest else { return "" }
        return "\(r.source.displayName) → \(r.target.displayName)"
    }

    private var mergeRebaseMessage: String {
        // Both options may need to switch branches (Merge → check out target;
        // Rebase → check out source). Wording it generically beats spelling
        // out two parallel sentences in one alert.
        return "If the destination branch isn't checked out, it'll switch first. Conflicts route to the Conflicts view."
    }
}

#if DEBUG
#Preview("Loaded") {
    @Previewable @State var theme = AppTheme()
    HistoryView(viewModel: RepositoryViewModel.preview)
        .environment(AppState.preview)
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
        .environment(AppState.preview)
        .frame(width: 1200, height: 720)
        .appTheme(theme)
}
#endif
