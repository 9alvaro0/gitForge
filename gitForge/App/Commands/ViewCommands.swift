import SwiftUI

/// View menu — workspace section switching for the redesigned shell, plus
/// the macOS-standard ⌘, slot routed to the Settings section.
struct ViewCommands: Commands {
    let appState: AppState

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            // One entry per section, in the order of the sidebar: ⌘ and the
            // number of its place, which stays put without a repository.
            let hasRepository = appState.catalog.activeRepository != nil
            ForEach(appState.ui.sidebarOrder.shortcuts(hasRepository: hasRepository)) { shortcut in
                Button(shortcut.section.showCommandTitle) {
                    appState.ui.workspaceSection = shortcut.section
                }
                .keyboardShortcut(shortcut.keyCharacter.map { KeyboardShortcut(KeyEquivalent($0), modifiers: .command) })
                .disabled(!shortcut.isEnabled)
                // The number is part of the item's identity: a section that
                // moves gets a fresh menu item with its new key equivalent
                // instead of relying on the old one being updated in place.
                .id(shortcut.number)
            }

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
