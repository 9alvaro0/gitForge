import Foundation
import Testing
@testable import gitForge

/// Navigation into and out of Settings (settings-redesign §4.1 and §4.7):
/// the pane shown is saved, and the section to go back to is kept by
/// whoever sets `workspaceSection`, however they do it.
@Suite("WorkspaceUI — Settings navigation")
@MainActor
struct WorkspaceUISettingsTests {
    private static let key = WorkspaceUI.settingsPaneKey

    @Test("Opening a pane shows Settings on it and remembers where it came from")
    func openWithPane() {
        TestDefaults.with { suite in
            let ui = WorkspaceUI(defaults: suite.defaults)
            ui.workspaceSection = .changes
            ui.openSettings(.accounts)
            #expect(ui.workspaceSection == .settings)
            #expect(ui.settingsPane == .accounts)
            #expect(ui.sectionBeforeSettings == .changes)
        }
    }

    @Test("Opening Settings without a pane shows the last one")
    func openKeepsLastPane() {
        TestDefaults.with { suite in
            let ui = WorkspaceUI(defaults: suite.defaults)
            ui.settingsPane = .git
            ui.workspaceSection = .history
            ui.openSettings()
            #expect(ui.workspaceSection == .settings)
            #expect(ui.settingsPane == .git)
        }
    }

    @Test("Closing Settings goes back to the section it was opened from")
    func closeReturns() {
        TestDefaults.with { suite in
            let ui = WorkspaceUI(defaults: suite.defaults)
            ui.workspaceSection = .pulls
            ui.openSettings()
            ui.closeSettings()
            #expect(ui.workspaceSection == .pulls)
            #expect(ui.sectionBeforeSettings == nil)
        }
    }

    @Test("Opening another pane from Settings keeps the original section")
    func reopenKeepsOrigin() {
        TestDefaults.with { suite in
            let ui = WorkspaceUI(defaults: suite.defaults)
            ui.workspaceSection = .history
            ui.openSettings(.general)
            ui.openSettings(.accounts)
            #expect(ui.sectionBeforeSettings == .history)
            ui.closeSettings()
            #expect(ui.workspaceSection == .history)
        }
    }

    @Test("Assigning the section directly records the origin too (⌘, and the menus)")
    func directAssignmentRecords() {
        TestDefaults.with { suite in
            let ui = WorkspaceUI(defaults: suite.defaults)
            ui.workspaceSection = .branches
            ui.workspaceSection = .settings
            #expect(ui.sectionBeforeSettings == .branches)
            ui.closeSettings()
            #expect(ui.workspaceSection == .branches)
        }
    }

    @Test("Leaving Settings by any other way forgets the origin")
    func leavingClearsOrigin() {
        TestDefaults.with { suite in
            let ui = WorkspaceUI(defaults: suite.defaults)
            ui.workspaceSection = .history
            ui.openSettings()
            ui.workspaceSection = .changes
            #expect(ui.sectionBeforeSettings == nil)

            ui.openSettings()
            #expect(ui.sectionBeforeSettings == .changes)
            ui.closeSettings()
            #expect(ui.workspaceSection == .changes)
        }
    }

    @Test("Closing outside Settings does nothing")
    func closeOutsideIsNoop() {
        TestDefaults.with { suite in
            let ui = WorkspaceUI(defaults: suite.defaults)
            ui.workspaceSection = .stashes
            ui.closeSettings()
            #expect(ui.workspaceSection == .stashes)
            #expect(ui.sectionBeforeSettings == nil)
        }
    }

    @Test("The pane is saved when it changes, and the next start opens on it")
    func paneSaved() {
        TestDefaults.with { suite in
            let ui = WorkspaceUI(defaults: suite.defaults)
            #expect(suite.defaults.string(forKey: Self.key) == nil)
            ui.settingsPane = .identities
            #expect(suite.defaults.string(forKey: Self.key) == "identities")

            let next = WorkspaceUI(defaults: suite.defaults)
            #expect(next.settingsPane == .identities)
        }
    }

    @Test("Setting the pane it already has doesn't write")
    func samePaneDoesNotSave() {
        TestDefaults.with { suite in
            let ui = WorkspaceUI(defaults: suite.defaults)
            ui.settingsPane = .general
            #expect(suite.defaults.string(forKey: Self.key) == nil)
        }
    }

    @Test("Opening a pane saves it, and opening Settings without one doesn't touch it")
    func openSavesPane() {
        TestDefaults.with { suite in
            let ui = WorkspaceUI(defaults: suite.defaults)
            ui.openSettings(.git)
            #expect(suite.defaults.string(forKey: Self.key) == "git")
            ui.closeSettings()
            ui.openSettings()
            #expect(suite.defaults.string(forKey: Self.key) == "git")
        }
    }

    @Test("An unknown or missing pane is General, and reading it writes nothing")
    func unknownPaneIsGeneral() {
        TestDefaults.with { suite in
            suite.defaults.set("reviews", forKey: Self.key)
            #expect(WorkspaceUI(defaults: suite.defaults).settingsPane == .general)
            #expect(suite.defaults.string(forKey: Self.key) == "reviews")
        }
        TestDefaults.with { suite in
            #expect(WorkspaceUI(defaults: suite.defaults).settingsPane == .general)
            #expect(suite.defaults.object(forKey: Self.key) == nil)
        }
    }

    @Test("New Profile and Follow Repository open their pane and raise a fresh request")
    func requests() {
        TestDefaults.with { suite in
            let ui = WorkspaceUI(defaults: suite.defaults)
            #expect(ui.newProfileRequest == nil)
            #expect(ui.followRepositoryRequest == nil)

            ui.requestNewProfile()
            #expect(ui.workspaceSection == .settings)
            #expect(ui.settingsPane == .identities)
            let first = ui.newProfileRequest
            #expect(first != nil)
            ui.requestNewProfile()
            #expect(ui.newProfileRequest != nil)
            #expect(ui.newProfileRequest != first)
            #expect(ui.followRepositoryRequest == nil)

            ui.requestFollowRepository()
            #expect(ui.workspaceSection == .settings)
            #expect(ui.settingsPane == .pullRequests)
            #expect(ui.followRepositoryRequest != nil)
        }
    }
}
