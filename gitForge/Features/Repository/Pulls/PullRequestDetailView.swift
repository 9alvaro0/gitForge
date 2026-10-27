import SwiftUI

/// What the pull request detail offers to do on disk. Inside a repository it
/// checks the branch out and resolves conflicts locally; without the
/// repository (Reviews) there is no local work, and one button takes their
/// place.
enum PullRequestLocalActions {
    /// The repository is open here: check out, resolve locally.
    case repository(integrate: () async -> RepositoryViewModel.IntegrationOutcome,
                    checkout: () async -> Result<String, Error>)
    /// Reviews: no local work; one button in their place.
    case remote(title: String, systemImage: String, action: @MainActor () -> Void)
}

/// Right-hand side of Pull requests: header, merge banner, then Checks /
/// Overview / Commits / Files.
struct PullRequestDetailView: View {
    let store: PullRequestStore
    let localActions: PullRequestLocalActions
    /// Names the repository in the header; for lists that mix several (Reviews).
    var showsRepository: Bool = false

    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme
    @State private var tab: Tab = .checks
    @State private var showLocalMergeConfirm = false
    @State private var showMergeSheet = false
    @State private var checkingOut = false

    enum Tab: String, DetailTab, Identifiable {
        case checks, overview, commits, files
        var id: String { rawValue }
        var label: String {
            switch self {
            case .checks:   String(localized: "Checks")
            case .overview: String(localized: "Overview")
            case .commits:  String(localized: "Commits")
            case .files:    String(localized: "Files")
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let pr = store.selected {
                VStack(alignment: .leading, spacing: Spacing.s12) {
                    PullRequestDetailHeader(
                        pullRequest: pr,
                        hostLabel: store.host?.provider.label,
                        reference: store.host?.provider.reference(pr.number),
                        repositoryLabel: showsRepository ? store.host?.slug : nil,
                        commitCount: store.commits.isEmpty ? nil : store.commits.count,
                        reviewers: store.detail?.reviewers ?? [],
                        labels: store.detail?.labels ?? [],
                        leading: headerLeadingAction,
                        actions: { compact in
                            AnyView(PullRequestActionsBar(store: store, compact: compact, onMerge: { showMergeSheet = true }))
                        }
                    )
                    // The review panel opens over the buttons from here, so a
                    // header relayout doesn't close it.
                    .overlayPreferenceValue(ReviewPanelAnchor.self) { anchor in
                        ReviewPanelHost(store: store, anchor: anchor)
                    }
                    tabBar
                }
                .padding(.horizontal, Spacing.s24)
                .padding(.top, Spacing.s20)
                .background(theme.colors.bgContent)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(theme.colors.separator).frame(height: 1)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.colors.bgElevated)
        .confirmationDialog(
            "Try integrating \(store.selected?.targetBranch ?? "target") locally?",
            isPresented: $showLocalMergeConfirm,
            titleVisibility: .visible
        ) {
            Button("Try local merge") { Task { await runLocalMerge() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(localMergeMessage)
        }
        // While its CI runs, the open PR's checks and merge status are read
        // again; only while the detail is on screen.
        .task(id: store.selected?.id) { await store.pollWhileRunning() }
        // A row's Approve or Merge, once the detail is in: the same panel
        // and sheet as the header's buttons.
        .onChange(of: store.quickActionCheckpoint, initial: true) {
            switch store.takeQuickAction() {
            case .perform(.approve): store.reviewPanel = .approve
            case .perform(.merge): showMergeSheet = true
            case .refused(let reason): appState.ui.activeToast = ToastMessage(message: reason, kind: .warn)
            case nil: break
            }
        }
        // Each opening reads the options afresh: nothing is remembered.
        .sheet(isPresented: $showMergeSheet, onDismiss: store.discardMergeOptions) {
            MergeSheet(store: store)
        }
    }

    /// Underlined tabs with counts, as in the artboard.
    private var tabBar: some View {
        HStack(spacing: Spacing.s4) {
            ForEach(Tab.allCases) { item in
                Button { tab = item } label: {
                    HStack(spacing: Spacing.s6) {
                        Text(item.label)
                            .textRole(.body, weight: tab == item ? .semibold : .regular)
                            .foregroundStyle(tab == item ? theme.colors.textPrimary : theme.colors.textSecondary)
                        if let count = count(for: item) {
                            Text("\(count)")
                                .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
                                .foregroundStyle(theme.colors.textTertiary)
                        }
                    }
                    .padding(.horizontal, Spacing.s12)
                    .frame(height: 34)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(tab == item ? theme.colors.accent : .clear).frame(height: 2)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
            Spacer(minLength: 0)
            if store.isLoadingDetail {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func count(for tab: Tab) -> Int? {
        switch tab {
        case .checks: store.checks.isEmpty ? nil : store.checks.count
        case .overview: nil
        case .commits: store.commits.isEmpty ? nil : store.commits.count
        case .files: store.files.isEmpty ? nil : store.files.count
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if let error = store.detailError, store.detail == nil {
                EmptyState(symbol: "exclamationmark.triangle", title: String(localized: "Couldn't load detail"), subtitle: error) {
                    GFButton(title: String(localized: "Retry")) { Task { await store.loadDetail() } }
                }
            } else {
                switch tab {
                case .checks:
                    ScrollView {
                        VStack(alignment: .leading, spacing: Spacing.s16) {
                            banner
                            PullRequestChecksTab(checks: store.checks, loading: store.isLoadingDetail)
                        }
                        .padding(Spacing.s24)
                    }
                case .overview:
                    PullRequestOverviewTab(
                        detail: store.detail,
                        banner: AnyView(banner),
                        localMergeRunning: store.localMergeRunning,
                        onTryLocalMerge: resolvesLocally ? { showLocalMergeConfirm = true } : nil
                    )
                case .commits:
                    PullRequestCommitsTab(commits: store.commits, loading: store.isLoadingDetail)
                case .files:
                    PullRequestFilesTab(store: store)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var banner: some View {
        if let readiness = store.mergeReadiness {
            MergeReadinessBanner(readiness: readiness)
        }
    }

    private var localMergeMessage: String {
        guard let pr = store.selected else { return "" }
        return String(localized: "Will fetch, check out \(pr.sourceBranch), and merge \(pr.targetBranch) into it. Conflicts route you to the Conflicts view.")
    }

    /// What takes the place of "Check out branch" in the header.
    private var headerLeadingAction: HeaderLeadingAction {
        switch localActions {
        case .repository:
            .checkout(running: checkingOut, action: { Task { await runCheckout() } })
        case .remote(let title, let systemImage, let action):
            .button(title: title, systemImage: systemImage, action: { action() })
        }
    }

    /// Only a repository on disk can integrate the branch ("Resolve locally").
    private var resolvesLocally: Bool {
        if case .repository = localActions { true } else { false }
    }

    private func runCheckout() async {
        guard case .repository(_, let checkoutBranch) = localActions else { return }
        checkingOut = true
        defer { checkingOut = false }
        switch await checkoutBranch() {
        case .success(let branch):
            appState.ui.activeToast = ToastMessage(message: String(localized: "Checked out \(branch)"), kind: .ok)
        case .failure(let error) where error is CancellationError:
            break
        case .failure(let error):
            appState.ui.activeToast = ToastMessage(
                message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription, kind: .error)
        }
    }

    private func runLocalMerge() async {
        guard case .repository(let integrateLocally, _) = localActions else { return }
        let outcome = await integrateLocally()
        let pr = store.selected
        switch outcome {
        case .clean:
            let message = pr.map {
                String(localized: "Already integrated — merged \($0.targetBranch) into \($0.sourceBranch) cleanly.")
            } ?? String(localized: "Already integrated — merged the target branch cleanly.")
            appState.ui.activeToast = ToastMessage(message: message, kind: .ok)
        case .conflicts:
            appState.ui.workspaceSection = .conflict
            appState.ui.activeToast = ToastMessage(message: String(localized: "Merge has conflicts — resolve to continue"), kind: .warn)
        case .cancelled:
            break
        case .failed(let message):
            appState.ui.activeToast = ToastMessage(message: message, kind: .error)
        }
    }
}

#Preview("Detail") {
    @Previewable @State var theme = AppTheme()
    PullRequestDetailView(store: .previewWithDetail, localActions: .preview)
        .previewAppState(.preview)
        .frame(width: 900, height: 720)
        .appTheme(theme)
}
