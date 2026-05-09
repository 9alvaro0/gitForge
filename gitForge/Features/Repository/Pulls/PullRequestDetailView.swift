import SwiftUI

/// Detail view for a single PR/MR. Tabs: Overview / Commits / Files.
struct PullRequestDetailView: View {
    @Bindable var viewModel: RepositoryViewModel

    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme
    @State private var tab: Tab = .overview
    @State private var showLocalMergeConfirm: Bool = false

    enum Tab: String, Hashable, CaseIterable, Identifiable {
        case overview, commits, files
        var id: String { rawValue }
        var label: String {
            switch self {
            case .overview: "Overview"
            case .commits:  "Commits"
            case .files:    "Files"
            }
        }
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.none) {
            if let pr = viewModel.selectedPullRequest {
                PullRequestDetailHeader(
                    pullRequest: pr,
                    onBack: { viewModel.closePullRequestDetail() }
                )
            }
            PullRequestDetailTabBar(tab: $tab, loading: viewModel.pullRequestDetailLoading)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.bg2)
        .confirmationDialog(
            "Try integrating \(viewModel.selectedPullRequest?.targetBranch ?? "target") locally?",
            isPresented: $showLocalMergeConfirm,
            titleVisibility: .visible
        ) {
            Button("Try local merge") { Task { await runLocalMerge() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(localMergeMessage)
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if let error = viewModel.pullRequestDetailError, viewModel.pullRequestDetail == nil {
                EmptyState(icon: .warn, title: "Couldn't load detail", subtitle: error) {
                    GFButton(title: "Retry", style: .primary) {
                        Task { await viewModel.loadPullRequestDetail() }
                    }
                }
            } else {
                switch tab {
                case .overview:
                    PullRequestOverviewTab(
                        detail: viewModel.pullRequestDetail,
                        localMergeRunning: viewModel.pullRequestLocalMergeRunning,
                        onTryLocalMerge: { showLocalMergeConfirm = true }
                    )
                case .commits:
                    PullRequestCommitsTab(
                        commits: viewModel.pullRequestCommits,
                        loading: viewModel.pullRequestDetailLoading
                    )
                case .files:
                    PullRequestFilesTab(
                        files: viewModel.pullRequestFiles,
                        loading: viewModel.pullRequestDetailLoading
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var localMergeMessage: String {
        guard let pr = viewModel.selectedPullRequest else { return "" }
        return "Will fetch, check out \(pr.sourceBranch), and merge \(pr.targetBranch) into it. Conflicts route you to the Conflicts view."
    }

    private func runLocalMerge() async {
        let outcome = await viewModel.attemptLocalMergeForPullRequest()
        let pr = viewModel.selectedPullRequest
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

#Preview("Detail — Loading") {
    @Previewable @State var theme = AppTheme()
    PullRequestDetailView(viewModel: .previewLoadingPullRequest)
        .previewAppState(.preview)
        .frame(width: 1200, height: 720)
        .appTheme(theme)
}

#Preview("Detail") {
    @Previewable @State var theme = AppTheme()
    PullRequestDetailView(viewModel: .previewWithPullRequestDetail)
        .previewAppState(.preview)
        .frame(width: 1200, height: 720)
        .appTheme(theme)
}
