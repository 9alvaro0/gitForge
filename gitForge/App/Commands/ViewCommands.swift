import SwiftUI

/// View menu — workspace section switching for the redesigned shell, plus
/// the macOS-standard ⌘, slot routed to the Settings section.
struct ViewCommands: Commands {
    let appState: AppState

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Show History") {
                appState.ui.workspaceSection = .history
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Show Changes") {
                appState.ui.workspaceSection = .changes
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("Show Branches") {
                appState.ui.workspaceSection = .branches
            }
            .keyboardShortcut("3", modifiers: .command)

            Button("Show Pull Requests") {
                appState.ui.workspaceSection = .pulls
            }
            .keyboardShortcut("4", modifiers: .command)

            Divider()

            Button("Open Command Palette…") {
                appState.ui.commandPaletteOpen = true
            }
            .keyboardShortcut("k", modifiers: .command)
        }

        // Native ⌘, slot. Routes the macOS-standard preferences shortcut
        // through our settings section instead of opening a separate window.
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                appState.ui.workspaceSection = .settings
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
