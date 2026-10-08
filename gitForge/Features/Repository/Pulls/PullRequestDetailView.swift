import SwiftUI

/// Detail view for a single PR/MR. Tabs: Overview / Commits / Files.
struct PullRequestDetailView: View {
    let store: PullRequestStore
    let integrateLocally: () async -> RepositoryViewModel.IntegrationOutcome

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
            if let pr = store.selected {
                PullRequestDetailHeader(
                    pullRequest: pr,
                    onBack: { store.closeDetail() }
                )
            }
            PullRequestDetailTabBar(tab: $tab, loading: store.isLoadingDetail)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.bg2)
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

    @ViewBuilder
    private var content: some View {
        Group {
            if let error = store.detailError, store.detail == nil {
                EmptyState(icon: .warn, title: "Couldn't load detail", subtitle: error) {
                    GFButton(title: "Retry", style: .primary) {
                        Task { await store.loadDetail() }
                    }
                }
            } else {
                switch tab {
                case .overview:
                    PullRequestOverviewTab(
                        detail: store.detail,
                        localMergeRunning: store.localMergeRunning,
                        onTryLocalMerge: { showLocalMergeConfirm = true }
                    )
                case .commits:
                    PullRequestCommitsTab(
                        commits: store.commits,
                        loading: store.isLoadingDetail
                    )
                case .files:
                    PullRequestFilesTab(
                        files: store.files,
                        loading: store.isLoadingDetail
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var localMergeMessage: String {
        guard let pr = store.selected else { return "" }
        return "Will fetch, check out \(pr.sourceBranch), and merge \(pr.targetBranch) into it. Conflicts route you to the Conflicts view."
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

#Preview("Detail — Loading") {
    @Previewable @State var theme = AppTheme()
    PullRequestDetailView(store: .previewLoadingDetail, integrateLocally: { .clean })
        .previewAppState(.preview)
        .frame(width: 1200, height: 720)
        .appTheme(theme)
}

#Preview("Detail") {
    @Previewable @State var theme = AppTheme()
    PullRequestDetailView(store: .previewWithDetail, integrateLocally: { .clean })
        .previewAppState(.preview)
        .frame(width: 1200, height: 720)
        .appTheme(theme)
}
