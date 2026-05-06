import SwiftUI

/// File menu — replaces the default `.newItem` group with repository-oriented
/// actions. macOS still owns ⌘W (close window); ⇧⌘W closes the active repo.
struct FileCommands: Commands {
    @Bindable var appState: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Branch...") {
                appState.newBranchSheetVisible = true
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(appState.activeViewModel == nil)

            Divider()

            Button("Open Repository...") {
                Task { await appState.presentOpenRepositoryPanel() }
            }
            .keyboardShortcut("o", modifiers: .command)

            Menu("Open Recent") {
                ForEach(appState.repositories) { repo in
                    Button(repo.name) {
                        Task { await appState.activate(repo) }
                    }
                }
                if appState.repositories.isEmpty {
                    Text("No Recent Repositories")
                }
            }

            Divider()

            Button("Close Repository") {
                appState.closeRepository()
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
            .disabled(appState.activeRepository == nil)
        }
    }
}
