import SwiftUI

/// Repository menu — git operations against the active repo. All entries
/// disable themselves when no repository is open, and remote operations gate
/// on the VM not being mid-fetch/pull/push to avoid concurrent work.
struct RepositoryCommands: Commands {
    @Bindable var appState: AppState

    var body: some Commands {
        CommandMenu("Repository") {
            Button("Refresh") {
                Task { await appState.activeViewModel?.refresh() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(appState.activeViewModel == nil)

            Divider()

            Button("Fetch") {
                Task { await appState.activeViewModel?.fetch() }
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(remoteBusy)

            Button("Pull") {
                Task { await appState.activeViewModel?.pull() }
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(remoteBusy)

            Button("Push") {
                Task { await appState.activeViewModel?.push() }
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(remoteBusy)

            Divider()

            Button("Commit...") {
                appState.activeViewModel?.currentTab = .changes
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(appState.activeViewModel == nil)

            Button("Stash All Changes") {
                guard let viewModel = appState.activeViewModel else { return }
                Task {
                    let result = await viewModel.stashAll()
                    if case .failure(let error) = result {
                        appState.presentedError = PresentedError(error: error, title: "Couldn’t stash")
                    }
                }
            }
            .disabled(appState.activeViewModel?.status.isClean ?? true)

            Divider()

            Button("Discard All Changes...") {
                appState.discardAllConfirmVisible = true
            }
            .disabled(appState.activeViewModel?.status.isClean ?? true)
        }
    }

    private var remoteBusy: Bool {
        guard let viewModel = appState.activeViewModel else { return true }
        return viewModel.remoteOperation != nil
    }
}
