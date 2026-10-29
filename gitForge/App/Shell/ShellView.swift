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
    /// The What's New sheet this window took from `appState.whatsNew`.
    @State private var whatsNewSheet: WhatsNewPresentation?
    /// The sidebar column's fold, bound to the split view so Settings can
    /// open it (`SidebarFoldState`).
    @State private var fold = SidebarFoldState()
    /// Whether the user left the sidebar folded, saved with the window so a
    /// relaunch restores it: an `.all` that every launch started from would
    /// unfold it. Set from `fold.isFolded`, which says folded while Settings
    /// holds a folded sidebar open.
    @SceneStorage("sidebar.folded") private var sidebarFolded = false
    /// The toast the pointer rests on, which waits until it leaves.
    @State private var hoveredToastID: UUID?

    /// Restarts the toast's countdown when the toast or its hover changes.
    private struct ToastTimer: Equatable {
        let toastID: UUID
        let paused: Bool
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $fold.visibility) {
            SidebarHost()
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)
        } detail: {
            mainColumn
                .navigationSubtitle(subtitle)
                .toolbar {
                    ShellToolbar(
                        // Settings is about the app, not the repository: no
                        // Fetch, Pull or Push there.
                        viewModel: isInSettings ? nil : appState.catalog.activeViewModel,
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
        // Without the sidebar there is no way to pick a pane, so Settings
        // unfolds it, and leaving puts it back as it was. What the user does
        // with it meanwhile is theirs: the flag only records what we did.
        .onChange(of: appState.ui.workspaceSection) { old, new in
            if new == .settings, old != .settings {
                fold.enterSettings()
            } else if old == .settings, new != .settings {
                fold.leaveSettings()
            }
        }
        // The fold the user chose is the one that is saved, never the one
        // Settings forced, and it comes back at launch.
        .onChange(of: fold.isFolded) { _, folded in sidebarFolded = folded }
        .onAppear { fold.restore(folded: sidebarFolded) }
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
                        appState.ui.openSettings(.accounts)
                    case .openURL(let url):
                        openURL(url)
                    case .copyText(let text):
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                })
                    // Keyed by toast: a hover that never saw the pointer leave
                    // (the toast went first) can't hold the next one.
                    .onHover { hoveredToastID = $0 ? toast.id : nil }
                    .padding(.bottom, Spacing.s16)
                    .transition(.opacity)
                    .task(id: ToastTimer(toastID: toast.id, paused: hoveredToastID == toast.id)) {
                        guard let delay = toast.dismissDelay(isHovered: hoveredToastID == toast.id) else { return }
                        // Cancelled: the pointer came in or another toast took
                        // over. Either way this countdown is over.
                        do { try await Task.sleep(for: delay) } catch { return }
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
            // The What's New sheet already says which version this is.
            if case .installed = notice, appState.whatsNew.showsSheetThisLaunch { return }
            appState.ui.activeToast = Self.toast(for: notice)
        }
        // What's New, after an update or from the Help menu. macOS shows one
        // sheet per window, so it waits while another one is up.
        .onChange(of: appState.whatsNew.pending?.id, initial: true) { claimWhatsNew() }
        .onChange(of: otherSheetUp) { claimWhatsNew() }
        .sheet(item: $whatsNewSheet, onDismiss: {
            appState.whatsNew.dismissed()
            claimWhatsNew()
        }) { presentation in
            WhatsNewSheet(presentation: presentation)
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
        // A pull refused over local changes asks instead of failing.
        .pullDiscardPrompt()
        // So does a checkout, from wherever it was started.
        .blockedCheckoutPrompt()
        // Once the sheet to connect an account closes, ⌘K searches the hosts
        // that asked for one again and a pasted link that waited for one
        // opens (R3 Ruling 14).
        .onChange(of: appState.ui.connectAccountRequest == nil) { _, closed in
            guard closed else { return }
            Task { await PaletteActionRouter(appState: appState).connectSheetClosed() }
        }
        // Same idea for success: commit, fetch, pull and push confirm what
        // landed, wherever they were started from.
        .onChange(of: appState.catalog.activeViewModel?.operationSuccess) { _, success in
            guard let success else { return }
            appState.ui.activeToast = ToastMessage(message: success.message, kind: .ok)
            appState.catalog.activeViewModel?.operationSuccess = nil
        }
    }

    private static func toast(for notice: Updater.LaunchNotice) -> ToastMessage {
        switch notice {
        case .installed(let version):
            return ToastMessage(message: String(localized: "Updated to gitForge \(version)"), kind: .ok)
        case .failed(let version):
            return ToastMessage(
                message: String(localized: "gitForge \(version) couldn’t be installed. Download it from GitHub and replace the app in Applications."),
                kind: .error,
                action: ToastAction(title: String(localized: "Download"), route: .openURL(Updater.releasesURL))
            )
        }
    }

    /// A sheet the shell presents is open in this window.
    private var otherSheetUp: Bool {
        appState.ui.cloneRequest != nil
            || appState.ui.connectAccountRequest != nil
            || appState.ui.addInstanceRequest != nil
            || appState.accountChooser.request != nil
    }

    private func claimWhatsNew() {
        guard whatsNewSheet == nil,
              let presentation = appState.whatsNew.claim(otherSheetUp: otherSheetUp) else { return }
        whatsNewSheet = presentation
    }

    private var isInSettings: Bool { appState.ui.workspaceSection == .settings }

    /// Branch and ahead/behind (the old status bar's left half), or the
    /// section's own context. Empty without an active repository. On Pull
    /// requests, Team and Mine show none; Open and Closed, the host. Settings
    /// shows the name of its pane, repository or not.
    private var subtitle: String {
        if isInSettings { return appState.ui.settingsPane.label }
        return appState.catalog.activeViewModel?.toolbarSubtitle(
            for: appState.ui.workspaceSection,
            pullsTab: PullsTab.shown(appState.reviews.tab, hasRepository: true)) ?? ""
    }

    @ViewBuilder
    private var mainColumn: some View {
        if let repo = appState.catalog.activeRepository {
            RepositoryHost(repository: repo)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch appState.ui.workspaceSection {
            case .settings: SettingsView()
            // Team and Mine need no repository (U1 Ruling 9).
            case .pulls:    PullsView(reviews: appState.reviews, repository: nil)
            default:        WelcomeView()
            }
        }
    }

    private var paletteOverlay: some View {
        let router = PaletteActionRouter(appState: appState)
        let reviews = appState.reviews
        return PaletteOverlay(
            repositories: appState.catalog.repositories,
            branches: appState.catalog.activeViewModel?.refs ?? [],
            commits: appState.catalog.activeViewModel?.history.commits ?? [],
            workingFiles: appState.catalog.activeViewModel?.workingCopy.status.files ?? [],
            pulls: appState.reviews.searchablePulls,
            unclonedRepos: appState.reviews.unclonedRepos,
            instances: appState.accounts.instances,
            // Read when the palette draws, not here: a search landing redraws
            // the palette alone.
            trailingItems: { query in
                CommandPaletteBuilder.searchItems(for: query, instances: reviews.searchInstances,
                                                  searches: reviews.hostSearches, followed: reviews.followedKeys)
            },
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
