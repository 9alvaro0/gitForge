import SwiftUI

/// File menu — replaces the default `.newItem` group with repository-oriented
/// actions. macOS still owns ⌘W (close window); ⇧⌘W closes the active repo.
struct FileCommands: Commands {
    let appState: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Branch…") {
                // Switch to Branches first so the view is mounted to host the
                // sheet — both entry points (this menu and the "+" tool button
                // in BranchesView) share that single presentation.
                appState.ui.workspaceSection = .branches
                appState.ui.newBranchSheetVisible = true
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(appState.catalog.activeViewModel == nil)

            Divider()

            Button("Open Repository…") {
                Task { await appState.presentOpenRepositoryPanel() }
            }
            .keyboardShortcut("o", modifiers: .command)

            Menu("Open Recent") {
                ForEach(appState.catalog.repositories) { repo in
                    Button(repo.name) {
                        Task { await appState.activate(repo) }
                    }
                }
                if appState.catalog.repositories.isEmpty {
                    Text("No Recent Repositories")
                }
            }

            Divider()

            Button("Close Repository") {
                appState.catalog.close()
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
            .disabled(appState.catalog.activeRepository == nil)
        }
    }
}
