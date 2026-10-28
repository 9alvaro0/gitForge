import SwiftUI
import Testing
@testable import gitForge

/// The sidebar's fold around Settings (settings-redesign §4.1): Settings
/// unfolds it, leaving puts it back, and what the user does meanwhile is
/// theirs. The fold that is saved for the next launch is the user's, never
/// the one Settings forces.
@Suite("Sidebar fold around Settings")
@MainActor
struct SidebarFoldStateTests {
    private static func folded() -> SidebarFoldState {
        SidebarFoldState(visibility: .detailOnly)
    }

    @Test("Entering Settings with the sidebar folded opens it and notes that it did")
    func enterFolded() {
        var state = Self.folded()
        state.enterSettings()
        #expect(state.visibility == .all)
        #expect(state.unfoldedForSettings)
    }

    @Test("Leaving Settings folds it again, and the note goes")
    func leaveFolds() {
        var state = Self.folded()
        state.enterSettings()
        state.leaveSettings()
        #expect(state.visibility == .detailOnly)
        #expect(!state.unfoldedForSettings)
    }

    @Test("With the sidebar open, entering and leaving leave it as it is and note nothing")
    func openStaysOpen() {
        var state = SidebarFoldState(visibility: .all)
        state.enterSettings()
        #expect(state == SidebarFoldState(visibility: .all))
        state.leaveSettings()
        #expect(state == SidebarFoldState(visibility: .all))

        var twoColumns = SidebarFoldState(visibility: .doubleColumn)
        twoColumns.enterSettings()
        twoColumns.leaveSettings()
        #expect(twoColumns == SidebarFoldState(visibility: .doubleColumn))
    }

    @Test("A fold or unfold by hand inside Settings doesn't change the note: leaving still follows it")
    func manualChangesKeepTheNote() {
        var foldedByHand = Self.folded()
        foldedByHand.enterSettings()
        foldedByHand.visibility = .detailOnly
        #expect(foldedByHand.unfoldedForSettings)
        foldedByHand.leaveSettings()
        #expect(foldedByHand.visibility == .detailOnly)

        var changedByHand = Self.folded()
        changedByHand.enterSettings()
        changedByHand.visibility = .doubleColumn
        #expect(changedByHand.unfoldedForSettings)
        changedByHand.leaveSettings()
        #expect(changedByHand.visibility == .detailOnly)
        #expect(!changedByHand.unfoldedForSettings)
    }

    @Test("Folding it by hand inside Settings, with it open when Settings began, is the user's: leaving keeps it folded")
    func manualFoldIsKept() {
        var state = SidebarFoldState(visibility: .all)
        state.enterSettings()
        state.visibility = .detailOnly
        state.leaveSettings()
        #expect(state.visibility == .detailOnly)
        #expect(!state.unfoldedForSettings)
    }

    @Test("Leaving Settings without having entered it does nothing")
    func leaveWithoutEntering() {
        var state = Self.folded()
        state.leaveSettings()
        #expect(state == Self.folded())
    }

    @Test("The fold to save is folded while the sidebar is, and while Settings holds it open")
    func savedFold() {
        #expect(!SidebarFoldState(visibility: .all).isFolded)
        #expect(!SidebarFoldState(visibility: .doubleColumn).isFolded)
        #expect(!SidebarFoldState(visibility: .automatic).isFolded)
        #expect(Self.folded().isFolded)

        var state = Self.folded()
        state.enterSettings()
        #expect(state.visibility == .all)
        #expect(state.isFolded, "Settings opened it: the user's fold is still folded")
        state.leaveSettings()
        #expect(state.isFolded)
    }

    @Test("A launch restores the saved fold, and an open sidebar keeps whatever shape it has")
    func restoring() {
        var folded = SidebarFoldState(visibility: .all)
        folded.restore(folded: true)
        #expect(folded.visibility == .detailOnly)
        #expect(folded.isFolded)

        var open = SidebarFoldState(visibility: .all)
        open.restore(folded: false)
        #expect(open == SidebarFoldState(visibility: .all))

        var twoColumns = SidebarFoldState(visibility: .doubleColumn)
        twoColumns.restore(folded: false)
        #expect(twoColumns.visibility == .doubleColumn)
    }

    @Test("Restoring never undoes what Settings did while it is open")
    func restoringInSettings() {
        var state = Self.folded()
        state.enterSettings()
        state.restore(folded: false)
        #expect(state.visibility == .all)
        #expect(state.unfoldedForSettings)
        state.restore(folded: true)
        #expect(state.visibility == .all)
        #expect(state.unfoldedForSettings)
    }

    @Test("Folded stays the saved fold through a whole visit to Settings and a relaunch")
    func savedFoldAcrossAVisit() {
        var state = SidebarFoldState(visibility: .all)
        state.visibility = .detailOnly                 // the user folds it
        var saved = state.isFolded
        #expect(saved)

        var relaunched = SidebarFoldState(visibility: .all)
        relaunched.restore(folded: saved)              // the next launch
        #expect(relaunched.visibility == .detailOnly)

        relaunched.enterSettings()
        saved = relaunched.isFolded
        #expect(saved, "while Settings forces it open")
        relaunched.leaveSettings()
        saved = relaunched.isFolded
        #expect(saved)
        #expect(relaunched.visibility == .detailOnly)

        // Unfolding it afterwards is what is saved from then on.
        relaunched.visibility = .all
        #expect(!relaunched.isFolded)
    }
}
