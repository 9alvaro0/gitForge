import Foundation
import Testing
@testable import gitForge

@Suite("SettingsPane")
@MainActor
struct SettingsPaneTests {
    @Test("The panes are in the order of the Settings sidebar, and their names are what is saved")
    func paneOrder() {
        #expect(SettingsPane.allCases == [.general, .appearance, .identities, .accounts, .git, .pullRequests])
        #expect(SettingsPane.allCases.map(\.rawValue) == ["general", "appearance", "identities", "accounts", "git", "pullRequests"])
        #expect(SettingsPane.pullRequests.rawValue == "pullRequests")
    }

    @Test("Every pane has its own name, symbol and id")
    func paneIdentity() {
        let panes = SettingsPane.allCases
        #expect(panes.allSatisfy { !$0.label.isEmpty && !$0.symbol.isEmpty })
        #expect(Set(panes.map(\.label)).count == panes.count)
        #expect(Set(panes.map(\.symbol)).count == panes.count)
        #expect(panes.map(\.id) == panes.map(\.rawValue))
    }

    @Test("The symbols are the ones the sidebar tiles show")
    func symbols() {
        #expect(SettingsPane.allCases.map(\.symbol) == [
            "gearshape", "paintpalette", "person.crop.circle", "key", "arrow.triangle.branch",
            WorkspaceSection.pulls.symbol,
        ])
    }

    @Test("Git is a name, not a word to translate")
    func gitIsNotTranslated() {
        #expect(SettingsPane.git.label == "Git")
    }
}
