import Foundation
import Testing
@testable import gitForge

@Suite("ConflictHunksColumn — keyboard focus navigation")
@MainActor
struct ConflictHunkFocusTests {

    @Test("Empty hunk list returns nil (so the key event stays unhandled)")
    func emptyListReturnsNil() {
        #expect(ConflictHunksColumn.advanceFocus(from: 0, by: 1, count: 0) == nil)
        #expect(ConflictHunksColumn.advanceFocus(from: 0, by: -1, count: 0) == nil)
    }

    @Test("Down arrow from 0 with 3 hunks → 1")
    func downIncrements() {
        #expect(ConflictHunksColumn.advanceFocus(from: 0, by: 1, count: 3) == 1)
    }

    @Test("Down arrow at last index → stays at last (no wrap)")
    func downAtEndClamps() {
        #expect(ConflictHunksColumn.advanceFocus(from: 2, by: 1, count: 3) == 2)
    }

    @Test("Up arrow from 1 → 0")
    func upDecrements() {
        #expect(ConflictHunksColumn.advanceFocus(from: 1, by: -1, count: 3) == 0)
    }

    @Test("Up arrow at index 0 → stays at 0 (no wrap)")
    func upAtStartClamps() {
        #expect(ConflictHunksColumn.advanceFocus(from: 0, by: -1, count: 3) == 0)
    }

    @Test("Starting index past the end is clamped to the last")
    func startingOutOfBoundsHigh() {
        #expect(ConflictHunksColumn.advanceFocus(from: 99, by: 1, count: 5) == 4)
        #expect(ConflictHunksColumn.advanceFocus(from: 99, by: -1, count: 5) == 4)
    }

    @Test("Starting index negative is clamped to 0")
    func startingOutOfBoundsLow() {
        #expect(ConflictHunksColumn.advanceFocus(from: -5, by: 1, count: 5) == 0)
        #expect(ConflictHunksColumn.advanceFocus(from: -5, by: -1, count: 5) == 0)
    }

    @Test("Single hunk: any arrow stays at 0")
    func singleHunkClamps() {
        #expect(ConflictHunksColumn.advanceFocus(from: 0, by: 1, count: 1) == 0)
        #expect(ConflictHunksColumn.advanceFocus(from: 0, by: -1, count: 1) == 0)
    }
}
