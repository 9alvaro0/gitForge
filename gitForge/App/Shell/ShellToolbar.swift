import SwiftUI

/// Toolbar items every repository screen shares (redesign spec §6.1): the
/// remote group and the ⌘K entry. Screens add their own items next to these.
struct ShellToolbar: ToolbarContent {
    let viewModel: RepositoryViewModel?
    let online: Bool
    /// A downloaded update; shows "Restart to Update" while set.
    var readyUpdate: Updater.ReadyUpdate? = nil
    let onOpenPalette: () -> Void
    var onInstallUpdate: () -> Void = {}

    var body: some ToolbarContent {
        // Leftmost of the shared items so it reads as app-level, not part
        // of the repository's remote actions.
        if let readyUpdate {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onInstallUpdate) {
                    Label("Restart to Update", systemImage: "arrow.down.circle")
                }
                .labelStyle(.titleAndIcon)
                .help("gitForge \(readyUpdate.version) is ready. Restart now to install it, or it installs when you quit.")
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
        if let viewModel {
            ToolbarItem(placement: .primaryAction) {
                RemoteToolbarGroup(viewModel: viewModel, online: online)
            }
        }
        // ⌘K is its own capsule, apart from the remote group and the
        // screen's actions.
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            Button(action: onOpenPalette) {
                Label("Search or run a command", systemImage: "magnifyingglass")
            }
            .labelStyle(.titleAndIcon)
            .help("Search or run a command (⌘K)")
        }
        // The screen's own actions (declared after these) get a capsule of
        // their own instead of sharing ⌘K's.
        ToolbarSpacer(.fixed, placement: .primaryAction)
    }
}
