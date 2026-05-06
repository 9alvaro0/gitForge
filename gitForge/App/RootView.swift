import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            switch appState.gitStatus {
            case .checking:
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .notFound:
                GitNotFoundView()
            case .available:
                ShellView()
            }
        }
        .appTheme(appState.theme)
        .alert(appState.presentedError?.title ?? "",
               isPresented: presentedErrorBinding) {
            Button("OK", role: .cancel) { appState.presentedError = nil }
        } message: {
            Text(appState.presentedError?.message ?? "")
        }
    }

    private var presentedErrorBinding: Binding<Bool> {
        Binding(
            get: { appState.presentedError != nil },
            set: { if !$0 { appState.presentedError = nil } }
        )
    }
}

private struct ShellView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme

    var body: some View {
        let title = activeTitle()
        WindowChrome(title: title) {
            ZStack(alignment: .top) {
                shellLayout
                if appState.commandPaletteOpen {
                    paletteOverlay
                        .transition(.opacity)
                        .zIndex(2)
                }
                if let toast = appState.activeToast {
                    ToastView(toast: toast) { appState.activeToast = nil }
                        .padding(.bottom, 40)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .transition(.opacity)
                        .zIndex(3)
                        .task {
                            try? await Task.sleep(nanoseconds: 2_400_000_000)
                            withAnimation { appState.activeToast = nil }
                        }
                }
            }
        }
        .background(KeyShortcutsCatcher())
    }

    private var shellLayout: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                RedesignedSidebar(
                    repositories: appState.repositories,
                    activeRepository: appState.activeRepository,
                    activeBranch: appState.activeViewModel?.currentBranchName,
                    aheadCount: appState.activeViewModel?.aheadCount ?? 0,
                    behindCount: appState.activeViewModel?.behindCount ?? 0,
                    dirtyCount: appState.activeViewModel?.status.files.count ?? 0,
                    activeSection: appState.workspaceSection,
                    unstagedBadge: appState.activeViewModel?.status.unstagedFiles.count ?? 0,
                    stashesBadge: appState.activeViewModel?.stashes.count ?? 0,
                    pullsBadge: 0,
                    conflictsBadge: appState.activeViewModel?.conflictFiles.filter { !$0.resolved }.count ?? 0,
                    identity: appState.globalConfig.identity,
                    onSelectRepo: { repo in Task { await appState.activate(repo) } },
                    onSelectSection: { appState.workspaceSection = $0 },
                    onOpenCommandPalette: { appState.commandPaletteOpen = true }
                )
                mainColumn
            }
            AppStatusBar(
                branch: appState.activeViewModel?.currentBranchName,
                ahead: appState.activeViewModel?.aheadCount ?? 0,
                behind: appState.activeViewModel?.behindCount ?? 0,
                staged: appState.activeViewModel?.status.stagedFiles.count ?? 0,
                unstaged: appState.activeViewModel?.status.unstagedFiles.count ?? 0,
                lastFetch: appState.activeViewModel?.lastFetchedAt,
                online: true
            )
        }
    }

    @ViewBuilder
    private var mainColumn: some View {
        if let repo = appState.activeRepository {
            RepositoryHost(repository: repo)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch appState.workspaceSection {
            case .clone:    CloneView()
            case .settings: SettingsView()
            default:        WelcomeView()
            }
        }
    }

    @ViewBuilder
    private var paletteOverlay: some View {
        let items = CommandPaletteBuilder.build(
            repositories: appState.repositories,
            branches: appState.activeViewModel?.refs ?? [],
            commits: appState.activeViewModel?.commits ?? [],
            workingFiles: appState.activeViewModel?.status.files ?? []
        )
        CommandPaletteView(
            items: items,
            onPick: { item in
                appState.commandPaletteOpen = false
                handle(action: item.action)
            },
            onClose: { appState.commandPaletteOpen = false }
        )
    }

    private func handle(action: PaletteAction) {
        switch action {
        case .openRepo(let url):
            Task { try? await appState.openRepository(at: url) }
        case .selectSection(let s):
            appState.workspaceSection = s
        case .fetch:
            Task {
                await appState.activeViewModel?.fetch()
                appState.activeToast = ToastMessage(message: "Fetched", kind: .ok)
            }
        case .pull:
            Task {
                await appState.activeViewModel?.pull()
                appState.activeToast = ToastMessage(message: "Pulled", kind: .ok)
            }
        case .push:
            Task {
                await appState.activeViewModel?.push()
                appState.activeToast = ToastMessage(message: "Pushed", kind: .ok)
            }
        case .stash:
            Task {
                _ = await appState.activeViewModel?.stashAll()
                appState.activeToast = ToastMessage(message: "Stashed", kind: .ok)
            }
        case .noop:
            break
        }
    }

    private func activeTitle() -> String {
        if let repo = appState.activeRepository {
            let parent = repo.url.deletingLastPathComponent().lastPathComponent
            return "\(parent)/\(repo.name) — GitForge"
        }
        return "GitForge"
    }
}

/// Listens for ⌘K + ⌘, etc. globally inside the redesigned shell.
private struct KeyShortcutsCatcher: View {
    @Environment(AppState.self) private var appState
    var body: some View {
        Color.clear
            .focusable()
            .onKeyPress(keys: ["k"]) { press in
                if press.modifiers.contains(.command) {
                    appState.commandPaletteOpen = true
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(keys: [","]) { press in
                if press.modifiers.contains(.command) {
                    appState.workspaceSection = .settings
                    return .handled
                }
                return .ignored
            }
    }
}

private struct RepositoryHost: View {
    let repository: Repository
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if let viewModel = appState.activeViewModel,
               viewModel.repository.url == repository.url {
                ContentRouter(viewModel: viewModel)
                    .id(repository.url)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: repository.url) {
            guard let viewModel = appState.activeViewModel else { return }
            await viewModel.loadInitial()
            await viewModel.loadRefs()
            await viewModel.refreshStatus()
            viewModel.startReactivity(
                autoFetchIntervalSeconds: appState.globalConfig.autoFetchInterval ?? 0
            )
        }
        .onDisappear {
            appState.activeViewModel?.stopReactivity()
        }
    }
}

private struct ContentRouter: View {
    @Bindable var viewModel: RepositoryViewModel
    @Environment(AppState.self) private var appState

    var body: some View {
        switch appState.workspaceSection {
        case .history:  HistoryView(viewModel: viewModel)
        case .changes:  StagingView(viewModel: viewModel)
        case .branches: BranchesView(viewModel: viewModel)
        case .stashes:  StashesView(viewModel: viewModel)
        case .pulls:    PullsView()
        case .conflict: ConflictView(viewModel: viewModel)
        case .clone:    CloneView()
        case .settings: SettingsView()
        }
    }
}

#Preview("Welcome (no active repo)") {
    RootView()
        .environment(AppState.preview)
        .frame(width: 1200, height: 720)
}

#Preview("Repository active") {
    RootView()
        .environment(AppState.previewWithActive)
        .frame(width: 1280, height: 760)
}

#Preview("Git not found") {
    RootView()
        .environment(AppState.previewMissingGit)
        .frame(width: 1100, height: 720)
}
