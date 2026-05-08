import SwiftUI

/// Top-level chrome of the redesigned UI: sidebar + main column + status bar,
/// plus the floating command palette and toast overlays. Renders only when
/// `gitStatus == .available`; the install gate lives in `RootView`.
struct ShellView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme

    /// How long a toast stays on screen before auto-dismissing.
    private static let toastLifetime: Duration = .milliseconds(2_400)

    var body: some View {
        let title = activeTitle()
        WindowChrome(title: title) {
            shellLayout
                .overlay {
                    if appState.ui.commandPaletteOpen {
                        paletteOverlay.transition(.opacity)
                    }
                }
                .overlay(alignment: .bottom) {
                    if let toast = appState.ui.activeToast {
                        ToastView(toast: toast) { appState.ui.activeToast = nil }
                            .padding(.bottom, DesignTokens.Spacing.xxxhuge)
                            .transition(.opacity)
                            .task(id: toast.id) {
                                try? await Task.sleep(for: Self.toastLifetime)
                                // Re-check that we're still the same toast —
                                // a newer one may have replaced us while we
                                // slept.
                                guard appState.ui.activeToast?.id == toast.id else { return }
                                withAnimation { appState.ui.activeToast = nil }
                            }
                    }
                }
        }
    }

    private var shellLayout: some View {
        VStack(spacing: DesignTokens.Spacing.none) {
            HStack(spacing: DesignTokens.Spacing.none) {
                SidebarHost()
                mainColumn
            }
            AppStatusBar(
                branch: appState.catalog.activeViewModel?.currentBranchName,
                ahead: appState.catalog.activeViewModel?.aheadCount ?? 0,
                behind: appState.catalog.activeViewModel?.behindCount ?? 0,
                staged: appState.catalog.activeViewModel?.status.stagedFiles.count ?? 0,
                unstaged: appState.catalog.activeViewModel?.status.unstagedFiles.count ?? 0,
                lastFetch: appState.catalog.activeViewModel?.lastFetchedAt,
                online: true
            )
        }
    }

    @ViewBuilder
    private var mainColumn: some View {
        if let repo = appState.catalog.activeRepository {
            RepositoryHost(repository: repo)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch appState.ui.workspaceSection {
            case .clone:    CloneView()
            case .settings: SettingsView()
            default:        WelcomeView()
            }
        }
    }

    private var paletteOverlay: some View {
        let router = PaletteActionRouter(appState: appState)
        return PaletteOverlay(
            repositories: appState.catalog.repositories,
            branches: appState.catalog.activeViewModel?.refs ?? [],
            commits: appState.catalog.activeViewModel?.commits ?? [],
            workingFiles: appState.catalog.activeViewModel?.status.files ?? [],
            onPick: { action in
                appState.ui.commandPaletteOpen = false
                router.route(action)
            },
            onClose: { appState.ui.commandPaletteOpen = false }
        )
    }

    private func activeTitle() -> String {
        if let repo = appState.catalog.activeRepository {
            let parent = repo.url.deletingLastPathComponent().lastPathComponent
            return "\(parent)/\(repo.name) — GitForge"
        }
        return "GitForge"
    }
}

#Preview("Shell — repo active") {
    ShellView()
        .previewAppState(.previewWithActive)
        .frame(width: 1280, height: 760)
}

#Preview("Shell — welcome") {
    ShellView()
        .previewAppState(.preview)
        .frame(width: 1200, height: 720)
}
