import SwiftUI

/// View menu — tab switching. The default sidebar toggle (⌃⌘S) is provided by
/// NavigationSplitView and lives in its own command group.
struct ViewCommands: Commands {
    let appState: AppState

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Show History") {
                appState.activeViewModel?.currentTab = .history
            }
            .keyboardShortcut("1", modifiers: .command)
            .disabled(appState.activeViewModel == nil)

            Button("Show Changes") {
                appState.activeViewModel?.currentTab = .changes
            }
            .keyboardShortcut("2", modifiers: .command)
            .disabled(appState.activeViewModel == nil)
        }
    }
}
