import SwiftUI

/// Repository menu — git operations against the active repo. All entries
/// disable themselves when no repository is open, and remote operations gate
/// on the VM not being mid-fetch/pull/push to avoid concurrent work.
struct RepositoryCommands: Commands {
    /// `@Bindable` is documented for use inside View bodies, not Commands —
    /// using it here compiled but suppressed Repository menu items in some
    /// builds. Keep it as a plain `let`.
    let appState: AppState

    var body: some Commands {
        // CommandMenu must contain at least one always-enabled item, otherwise
        // SwiftUI may collapse the menu when no repository is active.
        CommandMenu("Repository") {
            Button("Refresh") {
                Task { await appState.catalog.activeViewModel?.refresh() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(appState.catalog.activeViewModel == nil)

            Divider()

            Button("Fetch") {
                Task { await appState.catalog.activeViewModel?.fetch() }
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(remoteBusy)

            Button("Pull") {
                Task { await appState.catalog.activeViewModel?.pull() }
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(remoteBusy)

            Button("Push") {
                Task { await appState.catalog.activeViewModel?.push() }
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(remoteBusy)

            Divider()

            Button("Commit...") {
                appState.ui.workspaceSection = .changes
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(appState.catalog.activeViewModel == nil)

            Button("Stash All Changes") {
                guard let viewModel = appState.catalog.activeViewModel else { return }
                Task {
                    let result = await viewModel.stashAll()
                    if case .failure(let error) = result {
                        appState.ui.presentedError = PresentedError(error: error, title: "Couldn’t stash")
                    }
                }
            }
            .disabled(appState.catalog.activeViewModel?.status.isClean ?? true)

            Divider()

            Button("Discard All Changes...") {
                // Switch to Changes first so StagingView is mounted to host
                // the confirmation dialog — both entry points (this menu and
                // the "Discard all" tool button) share that single dialog.
                appState.ui.workspaceSection = .changes
                appState.ui.discardAllConfirmVisible = true
            }
            .disabled(appState.catalog.activeViewModel?.status.isClean ?? true)
        }
    }

    private var remoteBusy: Bool {
        guard let viewModel = appState.catalog.activeViewModel else { return true }
        return viewModel.remoteOperation != nil
    }
}
