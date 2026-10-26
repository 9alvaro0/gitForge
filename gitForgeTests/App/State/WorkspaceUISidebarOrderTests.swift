import Foundation
import Testing
@testable import gitForge

/// The sidebar order kept in the defaults (pulls-unified §4.7, Ruling 4):
/// one for the whole app, written when it changes and forgotten when it is
/// the default again.
@Suite("Sidebar order, saved")
@MainActor
struct WorkspaceUISidebarOrderTests {
    private static let key = WorkspaceUI.sidebarOrderKey

    @Test("With nothing saved the order is the default")
    func startsOnDefault() {
        TestDefaults.with { suite in
            #expect(WorkspaceUI(defaults: suite.defaults).sidebarOrder.isDefault)
        }
    }

    @Test("An edit is saved, and the next start has that order")
    func savesAndRestores() {
        TestDefaults.with { suite in
            let ui = WorkspaceUI(defaults: suite.defaults)
            ui.sidebarOrder.apply(.moveUp(.pulls))
            #expect(suite.defaults.stringArray(forKey: Self.key) == ["history", "changes", "pulls", "branches", "stashes", "conflict"])

            let next = WorkspaceUI(defaults: suite.defaults)
            #expect(next.sidebarOrder.sections == [.history, .changes, .pulls, .branches, .stashes, .conflict])
        }
    }

    @Test("Back to the default order the key is removed, by hand or by Reset Order")
    func backToDefaultForgets() {
        TestDefaults.with { suite in
            let ui = WorkspaceUI(defaults: suite.defaults)
            ui.sidebarOrder.apply(.moveUp(.pulls))
            #expect(suite.defaults.object(forKey: Self.key) != nil)
            ui.sidebarOrder.apply(.moveDown(.pulls))
            #expect(suite.defaults.object(forKey: Self.key) == nil)

            ui.sidebarOrder.apply(.moveDown(.history))
            #expect(suite.defaults.object(forKey: Self.key) != nil)
            ui.sidebarOrder.apply(.reset)
            #expect(suite.defaults.object(forKey: Self.key) == nil)
        }
    }

    @Test("An edit that changes nothing doesn't save", arguments: [
        SidebarOrder.Edit.moveUp(.history), .moveDown(.conflict), .move(fromOffsets: [9], toOffset: 0), .reset,
    ])
    func noChangeNoSave(edit: SidebarOrder.Edit) {
        TestDefaults.with { suite in
            let ui = WorkspaceUI(defaults: suite.defaults)
            ui.sidebarOrder.apply(edit)
            #expect(suite.defaults.object(forKey: Self.key) == nil)
        }
    }

    @Test("A saved value that isn't a list of sections starts on the default", arguments: [
        "history", [1, 2], ["pulls", "pulls"], [String](),
    ] as [any Sendable])
    func oddValues(saved: any Sendable) {
        TestDefaults.with { suite in
            suite.defaults.set(saved, forKey: Self.key)
            #expect(WorkspaceUI(defaults: suite.defaults).sidebarOrder.isDefault)
        }
    }

    @Test("Reading an incomplete order completes it without writing it back")
    func loadingDoesNotSave() {
        TestDefaults.with { suite in
            let saved = ["conflict", "pulls", "history", "changes", "branches"]
            suite.defaults.set(saved, forKey: Self.key)
            let ui = WorkspaceUI(defaults: suite.defaults)
            #expect(ui.sidebarOrder.sections == [.conflict, .pulls, .history, .changes, .stashes, .branches])
            #expect(suite.defaults.stringArray(forKey: Self.key) == saved)
        }
    }

    @Test("The order survives a relaunch of the app")
    func relaunchKeepsOrder() {
        TestDefaults.with { suite in
            let first = AppState.isolated(defaults: suite.defaults)
            first.ui.sidebarOrder.apply(.moveDown(.history))
            let second = AppState.isolated(defaults: suite.defaults)
            #expect(second.ui.sidebarOrder.sections == [.changes, .history, .branches, .pulls, .stashes, .conflict])
        }
    }
}
