import SwiftUI
import AppKit

/// Help menu — replaces the auto-generated entry to expose the project's
/// GitHub README and issue tracker, plus Sparkle's manual update check.
struct HelpCommands: Commands {
    static let documentationURL = URL(string: "https://github.com/9alvaro0/gitForge#readme")!
    static let issuesURL = URL(string: "https://github.com/9alvaro0/gitForge/issues/new")!

    let updater: Updater
    let appState: AppState

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Check for Updates…") {
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)

            Button("What's New in gitForge") {
                appState.whatsNew.showFromMenu()
            }
            .disabled(!appState.whatsNew.canShowFromMenu)

            Divider()

            Button("gitForge Documentation") {
                NSWorkspace.shared.open(Self.documentationURL)
            }
            Button("Report Issue") {
                NSWorkspace.shared.open(Self.issuesURL)
            }
        }
    }
}
