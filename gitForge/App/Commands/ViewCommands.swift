import SwiftUI

/// View menu — workspace section switching for the redesigned shell.
struct ViewCommands: Commands {
    let appState: AppState

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Show History") {
                appState.workspaceSection = .history
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Show Changes") {
                appState.workspaceSection = .changes
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("Show Branches") {
                appState.workspaceSection = .branches
            }
            .keyboardShortcut("3", modifiers: .command)

            Button("Show Pull Requests") {
                appState.workspaceSection = .pulls
            }
            .keyboardShortcut("4", modifiers: .command)

            Divider()

            Button("Open Command Palette…") {
                appState.commandPaletteOpen = true
            }
            .keyboardShortcut("k", modifiers: .command)
        }
    }
}
