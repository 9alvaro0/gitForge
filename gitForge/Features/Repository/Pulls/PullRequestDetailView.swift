import SwiftUI

/// Right-hand side of Pull requests: header, merge banner, then Checks /
/// Overview / Commits / Files.
struct PullRequestDetailView: View {
    let store: PullRequestStore
    let integrateLocally: () async -> RepositoryViewModel.IntegrationOutcome
    let checkoutBranch: () async -> Result<String, Error>

    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme
    @State private var tab: Tab = .checks
    @State private var showLocalMergeConfirm = false
    @State private var checkingOut = false

    enum Tab: String, DetailTab, Identifiable {
        case checks, overview, commits, files
        var id: String { rawValue }
        var label: String {
            switch self {
            case .checks:   "Checks"
            case .overview: "Overview"
            case .commits:  "Commits"
            case .files:    "Files"
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
                        commitCount: store.commits.isEmpty ? nil : store.commits.count,
                        reviewers: store.detail?.reviewers ?? [],
                        labels: store.detail?.labels ?? [],
                        checkingOut: checkingOut,
                        onCheckout: { Task { await runCheckout() } }
                    )
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
                EmptyState(icon: .warn, title: "Couldn't load detail", subtitle: error) {
                    GFButton(title: "Retry") { Task { await store.loadDetail() } }
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
                        onTryLocalMerge: { showLocalMergeConfirm = true }
                    )
                case .commits:
                    PullRequestCommitsTab(commits: store.commits, loading: store.isLoadingDetail)
                case .files:
                    PullRequestFilesTab(files: store.files, loading: store.isLoadingDetail)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var banner: some View {
        if let pr = store.selected, let detail = store.detail,
           let readiness = MergeReadiness.evaluate(state: pr.state, mergeable: detail.mergeable,
                                                   checks: store.checks, reviewers: detail.reviewers) {
            MergeReadinessBanner(readiness: readiness, hostLabel: store.host?.provider.label)
        }
    }

    private var localMergeMessage: String {
        guard let pr = store.selected else { return "" }
        return "Will fetch, check out \(pr.sourceBranch), and merge \(pr.targetBranch) into it. Conflicts route you to the Conflicts view."
    }

    private func runCheckout() async {
        checkingOut = true
        defer { checkingOut = false }
        switch await checkoutBranch() {
        case .success(let branch):
            appState.ui.activeToast = ToastMessage(message: "Checked out \(branch)", kind: .ok)
        case .failure(let error):
            appState.ui.activeToast = ToastMessage(
                message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription, kind: .error)
        }
    }

    private func runLocalMerge() async {
        let outcome = await integrateLocally()
        let pr = store.selected
        switch outcome {
        case .clean:
            let label = pr.map { "\($0.targetBranch) into \($0.sourceBranch)" } ?? "the target branch"
            appState.ui.activeToast = ToastMessage(message: "Already integrated — merged \(label) cleanly.", kind: .ok)
        case .conflicts:
            appState.ui.workspaceSection = .conflict
            appState.ui.activeToast = ToastMessage(message: "Merge has conflicts — resolve to continue", kind: .warn)
        case .failed(let message):
            appState.ui.activeToast = ToastMessage(message: message, kind: .error)
        }
    }
}

#Preview("Detail") {
    @Previewable @State var theme = AppTheme()
    PullRequestDetailView(store: .previewWithDetail, integrateLocally: { .clean },
                          checkoutBranch: { .success("feature") })
        .previewAppState(.preview)
        .frame(width: 900, height: 720)
        .appTheme(theme)
}
