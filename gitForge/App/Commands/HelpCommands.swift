import SwiftUI
import AppKit

/// Help menu — replaces the auto-generated entry to expose the project's
/// GitHub README and issue tracker.
struct HelpCommands: Commands {
    static let documentationURL = URL(string: "https://github.com/9alvaro0/gitForge#readme")!
    static let issuesURL = URL(string: "https://github.com/9alvaro0/gitForge/issues/new")!

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("gitForge Documentation") {
                NSWorkspace.shared.open(Self.documentationURL)
            }
            Button("Report Issue") {
                NSWorkspace.shared.open(Self.issuesURL)
            }
        }
    }
}
