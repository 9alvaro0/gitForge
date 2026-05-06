import SwiftUI
import AppKit

/// Help menu — replaces the auto-generated entry to add documentation, issue
/// reporter, and a placeholder for the local log viewer (#37).
struct HelpCommands: Commands {
    static let documentationURL = URL(string: "https://github.com/9alvaro0/gitForge#readme")!
    static let issuesURL = URL(string: "https://github.com/9alvaro0/gitForge/issues/new")!

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("gitForge Documentation") {
                NSWorkspace.shared.open(Self.documentationURL)
            }
            Button("Report Issue...") {
                NSWorkspace.shared.open(Self.issuesURL)
            }
        }
    }
}
