import SwiftUI

/// Switches the main column over the active `WorkspaceSection`. All nine
/// destinations share the same `RepositoryViewModel`, so this lives in `App/`
/// rather than any individual feature.
struct ContentRouter: View {
    @Bindable var viewModel: RepositoryViewModel
    @Environment(AppState.self) private var appState

    var body: some View {
        switch appState.ui.workspaceSection {
        case .history:  HistoryView(viewModel: viewModel)
        case .changes:  StagingView(viewModel: viewModel)
        case .branches: BranchesView(viewModel: viewModel)
        case .stashes:  StashesView(viewModel: viewModel)
        case .pulls:
            PullsView(reviews: appState.reviews,
                      repository: PullsRepository(
                          store: viewModel.pullRequests,
                          localActions: .repository(
                              integrate: { await viewModel.attemptLocalMergeForPullRequest() },
                              checkout: { await viewModel.checkoutSelectedPullRequest() })))
        case .conflict: ConflictView(viewModel: viewModel)
        case .settings: SettingsView()
        }
    }
}

#Preview("History") {
    ContentRouter(viewModel: .preview)
        .previewAppState(.previewWithActive)
        .frame(width: 1100, height: 720)
}
