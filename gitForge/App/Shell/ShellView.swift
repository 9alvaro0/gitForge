import SwiftUI

/// Top-level chrome: native split view (sidebar + main column) with the
/// shared toolbar, plus the floating command palette and toast overlays.
/// Renders only when `gitStatus == .available`; the install gate lives in
/// `RootView`.
struct ShellView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme

    var body: some View {
        NavigationSplitView {
            SidebarHost()
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)
        } detail: {
            mainColumn
                .navigationSubtitle(subtitle)
                .toolbar {
                    ShellToolbar(
                        viewModel: appState.catalog.activeViewModel,
                        online: appState.network.isOnline,
                        onOpenPalette: { appState.ui.commandPaletteOpen = true }
                    )
                }
        }
        // The accent tints the prominent toolbar actions (New branch,
        // Continue, Stash changes…). Label styles are set per item: a global
        // `.titleAndIcon` also titles the system sidebar toggle, which then
        // no longer fits and drops into the toolbar overflow menu.
        .tint(theme.colors.accentFill)
        .preferredColorScheme(preferredScheme)
        .overlay {
            if appState.ui.commandPaletteOpen {
                paletteOverlay.transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = appState.ui.activeToast {
                ToastView(toast: toast) { appState.ui.activeToast = nil }
                    .padding(.bottom, Spacing.s16)
                    .transition(.opacity)
                    .task(id: toast.id) {
                        guard let lifetime = toast.autoDismissAfter else { return }
                        try? await Task.sleep(for: lifetime)
                        // A newer toast may have replaced this one while we slept.
                        guard appState.ui.activeToast?.id == toast.id else { return }
                        withAnimation { appState.ui.activeToast = nil }
                    }
            }
        }
        // Centralised error reporting for fetch/pull/push/tag pushes —
        // covers every entry point (menu, toolbar, command palette).
        .onChange(of: appState.catalog.activeViewModel?.remoteFailure) { _, failure in
            guard let failure else { return }
            appState.ui.activeToast = ToastMessage(message: failure.toastMessage, kind: .error)
            appState.catalog.activeViewModel?.remoteFailure = nil
        }
    }

    /// Branch and ahead/behind (the old status bar's left half), or the
    /// section's own context. Empty without an active repository.
    private var subtitle: String {
        appState.catalog.activeViewModel?.toolbarSubtitle(for: appState.ui.workspaceSection) ?? ""
    }

    /// `.system` returns `nil` so SwiftUI keeps the OS scheme; explicit modes
    /// force the window to follow the user's pick.
    private var preferredScheme: ColorScheme? {
        switch theme.mode {
        case .system: nil
        case .dark: .dark
        case .light: .light
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
