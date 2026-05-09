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
    let vm: RepositoryViewModel = {
        let v = RepositoryViewModel.preview
        v.pullRequestsHost = RemoteHost(provider: .github, host: "github.com", owner: "9alvaro0", repo: "gitForge")
        v.selectedPullRequest = PullRequest.previewSamples.first
        v.pullRequestDetailLoading = true
        return v
    }()
    PullRequestDetailView(viewModel: vm)
        .previewAppState(.preview)
        .frame(width: 1200, height: 720)
        .appTheme(theme)
}

#Preview("Detail") {
    @Previewable @State var theme = AppTheme()
    let vm: RepositoryViewModel = {
        let v = RepositoryViewModel.preview
        v.pullRequestsHost = RemoteHost(provider: .github, host: "github.com", owner: "9alvaro0", repo: "gitForge")
        v.selectedPullRequest = PullRequest.previewSamples.first
        v.pullRequestDetail = PullRequestDetail(
            pull: PullRequest.previewSamples.first!,
            descriptionMarkdown: "Adds the **PR/MR** integration with `Phase 2` detail view.\n\n- Description\n- Commits\n- Files",
            labels: ["feature", "phase-2"],
            reviewers: [.init(login: "reviewer1", approved: true), .init(login: "reviewer2", approved: false)],
            assignees: ["9alvaro0"],
            mergeable: true,
            ciStatus: CIStatus(state: .success, description: "All checks passed", webURL: nil)
        )
        v.pullRequestCommits = [
            PullRequestCommit(sha: "abc1234abcdef", subject: "feat: add PR detail view", authorName: "9alvaro0", authorDate: Date(timeIntervalSinceNow: -3600)),
            PullRequestCommit(sha: "def5678abcdef", subject: "refactor: split provider", authorName: "9alvaro0", authorDate: Date(timeIntervalSinceNow: -7200)),
        ]
        v.pullRequestFiles = [
            PullRequestFileChange(path: "Sources/Foo.swift", oldPath: nil, status: .modified, additions: 42, deletions: 5,
                                  patch: "@@ -1,3 +1,5 @@\n line1\n-old\n+new\n+added\n line3"),
            PullRequestFileChange(path: "README.md", oldPath: nil, status: .added, additions: 10, deletions: 0,
                                  patch: "@@ -0,0 +1,3 @@\n+# Title\n+\n+Body"),
        ]
        return v
    }()
    PullRequestDetailView(viewModel: vm)
        .previewAppState(.preview)
        .frame(width: 1200, height: 720)
        .appTheme(theme)
}
