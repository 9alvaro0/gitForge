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
            // Identity first — two cheap config reads — so the sidebar doesn't
            // briefly badge a custom-overridden repo as "Global" while a slow
            // `git log` is still loading. After that, status / log / refs run
            // concurrently: cli is an actor so they serialize internally, but
            // submitting `git status` alongside the heavier work lets the
            // Changes view paint without waiting for `git log` to finish.
            await viewModel.refreshIdentity()
            async let statusTask: Void = viewModel.refreshStatus()
            async let initialTask: Void = viewModel.loadInitial()
            async let refsTask: Void = viewModel.loadRefs()
            // Conflict state must land before reactivity starts so guards
            // like the amend/rebase rejections see `mergeState != .clean`
            // when the user opens a repo that's mid-integration from terminal.
            // Without this, a commit/stash/rebase attempted right after open
            // would fall through guards and fail cryptically from git.
            async let conflictTask: Void = viewModel.loadConflictState()
            _ = await statusTask
            _ = await initialTask
            _ = await refsTask
            _ = await conflictTask
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
