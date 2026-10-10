import Testing
@testable import gitForge

@Suite("History branch drop HUD")
@MainActor
struct BranchDropTrackerTests {

    @Test("Crossing from one row to the next keeps the newer target, whatever the event order")
    func crossingRows() {
        let tracker = BranchDropTracker()
        let a = BranchDropIntent.commit(shortSha: "aaaaaaa", subject: "A")
        let b = BranchDropIntent.commit(shortSha: "bbbbbbb", subject: "B")
        tracker.hover(a, isOver: true)
        tracker.hover(b, isOver: true)   // enter B before leaving A
        tracker.hover(a, isOver: false)
        #expect(tracker.intent == b)
        tracker.hover(b, isOver: false)
        #expect(tracker.intent == nil)
    }

    @Test("Clear drops the intent after a drop")
    func clear() {
        let tracker = BranchDropTracker()
        tracker.hover(.branch(name: "main"), isOver: true)
        tracker.clear()
        #expect(tracker.intent == nil)
    }

    @Test("The HUD names what the drop will do")
    func copy() {
        #expect(BranchDropIntent.branch(name: "main").title == "Merge or rebase onto main")
        #expect(BranchDropIntent.commit(shortSha: "a3f9c21", subject: "Fix").title == "Move the branch to a3f9c21")
    }
}
