import CoreGraphics
import Testing
@testable import gitForge

@Suite("Command palette — hover follows the pointer, not the scroll")
struct PointerIntentTests {
    @Test("A still pointer never selects; a moved one does once per move")
    func movement() {
        var pointer = PointerIntent()
        pointer.reset(at: CGPoint(x: 10, y: 10))
        // Arrow keys scroll a row under the pointer, which hasn't moved.
        let scrolledUnder = pointer.moved(to: CGPoint(x: 10, y: 10))
        let movedOnce = pointer.moved(to: CGPoint(x: 12, y: 30))
        let stillAgain = pointer.moved(to: CGPoint(x: 12, y: 30))
        #expect(!scrolledUnder)
        #expect(movedOnce)
        #expect(!stillAgain)
    }
}
