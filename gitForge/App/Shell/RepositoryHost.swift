import SwiftUI

/// Bridges a `Repository` from the sidebar selection to the live
/// `RepositoryViewModel`. While the VM is still being created (or doesn't yet
/// match the requested repo URL), shows a placeholder; once it's ready, hands
/// off to `ContentRouter` and starts/stops reactivity around the lifetime of
/// this view.
struct RepositoryHost: View {
    let repository: Repository
    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme

    var body: some View {
        Group {
            if let viewModel = appState.catalog.activeViewModel,
               viewModel.repository.url == repository.url {
                ContentRouter(viewModel: viewModel)
                    .id(repository.url)
            } else {
                VStack(spacing: DesignTokens.Spacing.lg) {
                    ProgressView().controlSize(.regular)
                    Text("Opening \(repository.url.lastPathComponent)…")
                        .font(AppFont.mono(11, family: theme.monoFont))
                        .foregroundStyle(theme.palette.fg3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.palette.bg2)
            }
        }
        .task(id: repository.url) {
            guard let viewModel = appState.catalog.activeViewModel else { return }
            await viewModel.loadInitial()
            await viewModel.loadRefs()
            await viewModel.refreshStatus()
            viewModel.startReactivity(
                autoFetchIntervalSeconds: appState.gitEnvironment.globalConfig.autoFetchInterval ?? 0
            )
        }
        .onDisappear {
            appState.catalog.activeViewModel?.stopReactivity()
        }
    }
}

#Preview("RepositoryHost") {
    RepositoryHost(repository: .preview)
        .previewAppState(.previewWithActive)
        .frame(width: 1100, height: 720)
}
