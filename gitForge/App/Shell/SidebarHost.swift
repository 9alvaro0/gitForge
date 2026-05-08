import SwiftUI
import AppKit

/// Hosts the redesigned sidebar so its 17-parameter call site lives in one
/// dedicated view instead of bloating `ShellView.body`. Reads `AppState` from
/// the environment and dispatches actions directly.
struct SidebarHost: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        RedesignedSidebar(
            repositories: appState.catalog.repositories,
            activeRepository: appState.catalog.activeRepository,
            statusFor: statusFor,
            activeSection: appState.ui.workspaceSection,
            unstagedBadge: appState.catalog.activeViewModel?.status.unstagedFiles.count ?? 0,
            stashesBadge: appState.catalog.activeViewModel?.stashes.count ?? 0,
            pullsBadge: appState.catalog.activeViewModel?.pullRequests.count ?? 0,
            conflictsBadge: appState.catalog.activeViewModel?.conflictFiles.filter { !$0.resolved }.count ?? 0,
            identity: appState.gitEnvironment.globalConfig.identity,
            onSelectRepo: { repo in Task { await appState.activate(repo) } },
            onRemoveRepo: { repo in Task { await appState.catalog.remove(repo.url) } },
            onRevealRepo: { repo in NSWorkspace.shared.activateFileViewerSelecting([repo.url]) },
            onOpenExisting: { Task { await appState.presentOpenRepositoryPanel() } },
            onCloneNew: { appState.ui.workspaceSection = .clone },
            onSelectSection: { appState.ui.workspaceSection = $0 },
            onOpenCommandPalette: { appState.ui.commandPaletteOpen = true }
        )
    }

    /// Active repo: read straight from the live ViewModel so the pills update
    /// instantly as the user works. Other repos: cached snapshot refreshed
    /// every 30s by AppState's background poller.
    private func statusFor(_ repo: Repository) -> RepoStatusSnapshot {
        if let active = appState.catalog.activeRepository,
           active.id == repo.id,
           let vm = appState.catalog.activeViewModel,
           vm.hasLoadedStatusOnce {
            return RepoStatusSnapshot(
                branch: vm.currentBranchName,
                dirty: vm.status.files.count,
                ahead: vm.aheadCount,
                behind: vm.behindCount,
                loaded: true
            )
        }
        return appState.catalog.repositoryStatuses[repo.url] ?? .empty
    }
}

#Preview("Sidebar — repo active") {
    SidebarHost()
        .previewAppState(.previewWithActive)
        .frame(width: 280, height: 720)
}

#Preview("Sidebar — welcome") {
    SidebarHost()
        .previewAppState(.preview)
        .frame(width: 280, height: 720)
}
