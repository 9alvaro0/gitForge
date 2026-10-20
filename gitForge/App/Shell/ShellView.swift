import SwiftUI

/// Top-level chrome: native split view (sidebar + main column) with the
/// shared toolbar, plus the floating command palette and toast overlays.
/// Renders only when `gitStatus == .available`; the install gate lives in
/// `RootView`.
struct ShellView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme
    /// Optional so previews and tests run without Sparkle.
    @Environment(Updater.self) private var updater: Updater?
    @Environment(\.openURL) private var openURL

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
                        readyUpdate: updater?.readyUpdate,
                        onOpenPalette: { appState.ui.commandPaletteOpen = true },
                        onInstallUpdate: { updater?.installAndRelaunch() }
                    )
                }
        }
        // The accent tints the prominent toolbar actions (New branch,
        // Continue, Stash changes…). Label styles are set per item: a global
        // `.titleAndIcon` also titles the system sidebar toggle, which then
        // no longer fits and drops into the toolbar overflow menu.
        .tint(theme.colors.accentFill)
        .overlay {
            if appState.ui.commandPaletteOpen {
                paletteOverlay.transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = appState.ui.activeToast {
                ToastView(toast: toast, onDismiss: { appState.ui.activeToast = nil }, onAction: { action in
                    appState.ui.activeToast = nil
                    switch action.route {
                    case .reconnectAccount(let instanceId, let accountId):
                        appState.ui.connectAccountRequest = ConnectAccountRequest(instanceId: instanceId, replacing: accountId)
                    case .openAccounts:
                        appState.ui.openSettings(at: .accounts)
                    case .openURL(let url):
                        openURL(url)
                    }
                })
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
        // Once per launch: whether the update installed on the last quit
        // landed. A failure only shows after the automatic retry failed too.
        .onChange(of: updater?.launchNotice, initial: true) { _, notice in
            guard let notice else { return }
            updater?.launchNotice = nil
            appState.ui.activeToast = Self.toast(for: notice)
        }
        .sheet(item: Bindable(appState.ui).cloneRequest) { request in
            CloneSheet(request: request)
        }
        // While the clone sheet is up it presents these itself.
        .requestSheets(enabled: appState.ui.cloneRequest == nil)
        // Centralised error reporting for fetch/pull/push/tag pushes —
        // covers every entry point (menu, toolbar, command palette).
        .onChange(of: appState.catalog.activeViewModel?.remoteFailure) { _, failure in
            guard let failure else { return }
            guard failure != .cancelled else {
                appState.catalog.activeViewModel?.remoteFailure = nil
                return
            }
            appState.ui.activeToast = ToastMessage(message: failure.toastMessage, kind: .error,
                                                   action: AccountToastAction.action(for: failure,
                                                                                     instances: appState.accounts.instances,
                                                                                     accounts: appState.accounts.accounts))
            appState.catalog.activeViewModel?.remoteFailure = nil
        }
    }

    private static func toast(for notice: Updater.LaunchNotice) -> ToastMessage {
        switch notice {
        case .installed(let version):
            return ToastMessage(message: "Updated to gitForge \(version)", kind: .ok)
        case .failed(let version):
            return ToastMessage(
                message: "gitForge \(version) couldn’t be installed. Download it from GitHub and replace the app in Applications.",
                kind: .error,
                action: ToastAction(title: "Download", route: .openURL(Updater.releasesURL))
            )
        }
    }

    /// Branch and ahead/behind (the old status bar's left half), or the
    /// section's own context. Empty without an active repository.
    private var subtitle: String {
        appState.catalog.activeViewModel?.toolbarSubtitle(for: appState.ui.workspaceSection) ?? ""
    }

    @ViewBuilder
    private var mainColumn: some View {
        if let repo = appState.catalog.activeRepository {
            RepositoryHost(repository: repo)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch appState.ui.workspaceSection {
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
            commits: appState.catalog.activeViewModel?.history.commits ?? [],
            workingFiles: appState.catalog.activeViewModel?.workingCopy.status.files ?? [],
            onPick: { action, keepOpen in
                if !keepOpen { appState.ui.commandPaletteOpen = false }
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
