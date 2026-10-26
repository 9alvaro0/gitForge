import Foundation
import Testing
@testable import gitForge

/// The order of the sidebar's sections (pulls-unified §4.7): restoring a
/// saved one, editing it, and which sections the list shows.
@Suite("Sidebar order")
@MainActor
struct SidebarOrderTests {
    private static let defaultSections: [WorkspaceSection] = [.history, .changes, .branches, .pulls, .stashes, .conflict]

    private static let custom = ["conflict", "pulls", "history", "changes", "branches", "stashes"]

    @Test("The default order has Pull requests fourth")
    func defaultOrder() {
        let order = SidebarOrder()
        #expect(order.sections == Self.defaultSections)
        #expect(order.isDefault)
        #expect(order.savedValue == nil)
    }

    @Test("A saved order comes back as it was")
    func restoresSaved() {
        let order = SidebarOrder(saved: Self.custom)
        #expect(order.sections == [.conflict, .pulls, .history, .changes, .branches, .stashes])
        #expect(!order.isDefault)
        #expect(order.savedValue == Self.custom)
    }

    @Test("A section missing from the saved order takes its default position", arguments: [
        (["pulls", "history", "changes", "branches", "stashes"],
         [WorkspaceSection.pulls, .history, .changes, .branches, .stashes, .conflict]),
        (["pulls", "history", "changes", "branches", "conflict"],
         [.pulls, .history, .changes, .branches, .stashes, .conflict]),
        (["pulls", "changes", "branches", "stashes", "conflict"],
         [.history, .pulls, .changes, .branches, .stashes, .conflict]),
    ])
    func completesMissing(saved: [String], expected: [WorkspaceSection]) {
        #expect(SidebarOrder(saved: saved).sections == expected)
    }

    @Test("Unknown, Settings and repeated values are dropped, the rest is completed")
    func dropsUnknown() {
        let order = SidebarOrder(saved: ["reviews", "pulls", "settings", "history", "pulls", "x"])
        #expect(order.sections == [.pulls, .changes, .branches, .history, .stashes, .conflict])
    }

    @Test("Nothing saved, or an empty list, is the default order", arguments: [nil, [String]()])
    func emptyIsDefault(saved: [String]?) {
        #expect(SidebarOrder(saved: saved).isDefault)
    }

    @Test("Moving a section up or down swaps it with its neighbour")
    func moveUpAndDown() {
        var order = SidebarOrder()
        order.apply(.moveUp(.pulls))
        #expect(order.sections == [.history, .changes, .pulls, .branches, .stashes, .conflict])
        order.apply(.moveDown(.history))
        #expect(order.sections == [.changes, .history, .pulls, .branches, .stashes, .conflict])
    }

    @Test("The first can't go up, the last can't go down")
    func edgesDoNothing() {
        var order = SidebarOrder()
        #expect(order.canMoveUp(.history) == false)
        #expect(order.canMoveDown(.conflict) == false)
        #expect(order.canMoveUp(.changes))
        #expect(order.canMoveDown(.stashes))
        order.apply(.moveUp(.history))
        order.apply(.moveDown(.conflict))
        #expect(order.sections == Self.defaultSections)
    }

    @Test("A drag moves the section to the offset the list gives")
    func dragMoves() {
        var toTop = SidebarOrder()
        toTop.apply(.move(fromOffsets: [5], toOffset: 0))
        #expect(toTop.sections == [.conflict, .history, .changes, .branches, .pulls, .stashes])

        var toBottom = SidebarOrder()
        toBottom.apply(.move(fromOffsets: [0], toOffset: 6))
        #expect(toBottom.sections == [.changes, .branches, .pulls, .stashes, .conflict, .history])
    }

    @Test("A drag with offsets that no longer fit changes nothing", arguments: [
        ([6], 0), ([], 1), ([0], 7), ([2, 9], 0), ([-1], 2), ([1], -1),
    ] as [([Int], Int)])
    func invalidMoveIgnored(offsets: [Int], destination: Int) {
        var order = SidebarOrder()
        order.apply(.move(fromOffsets: IndexSet(offsets), toOffset: destination))
        #expect(order.sections == Self.defaultSections)
    }

    @Test("Reset Order goes back to the default")
    func resetRestoresDefault() {
        var order = SidebarOrder()
        order.apply(.moveUp(.pulls))
        order.apply(.move(fromOffsets: [5], toOffset: 0))
        #expect(!order.isDefault)
        order.apply(.reset)
        #expect(order.isDefault)
        #expect(order.savedValue == nil)
    }

    @Test("With a repository the list shows the order; without one, Pull requests alone")
    func visibleSections() {
        for order in [SidebarOrder(), SidebarOrder(saved: Self.custom)] {
            #expect(order.visible(hasRepository: true) == order.sections)
            #expect(order.visible(hasRepository: false) == [.pulls])
        }
    }
}
