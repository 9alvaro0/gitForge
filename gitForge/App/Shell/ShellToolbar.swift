import SwiftUI

/// Toolbar items every repository screen shares (redesign spec §6.1): the
/// remote group and the ⌘K entry. Screens add their own items next to these.
struct ShellToolbar: ToolbarContent {
    let viewModel: RepositoryViewModel?
    let online: Bool
    let onOpenPalette: () -> Void

    var body: some ToolbarContent {
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
