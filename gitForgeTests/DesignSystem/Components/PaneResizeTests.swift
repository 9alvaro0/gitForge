import Foundation
import Testing
@testable import gitForge

@Suite("Pane resize")
struct PaneResizeTests {

    @Test("A drag sizes the pane within its bounds, the minimum winning when they cross")
    func clamps() {
        #expect(PaneResize.resolve(proposed: 50, min: 60, max: 200) == .size(60))
        #expect(PaneResize.resolve(proposed: 300, min: 60, max: 200) == .size(200))
        #expect(PaneResize.resolve(proposed: 120, min: 60, max: 200) == .size(120))
        #expect(PaneResize.resolve(proposed: 120, min: 60, max: 40) == .size(60))
    }

    @Test("Without a collapse point the pane stops at its minimum")
    func neverCollapses() {
        #expect(PaneResize.resolve(proposed: -400, min: 96, max: 600) == .size(96))
    }

    @Test("Dragged past the collapse point the pane collapses, short of it it holds its minimum")
    func collapses() {
        let below = PaneResize.collapseThreshold(min: 96)
        #expect(below == 48)
        #expect(PaneResize.resolve(proposed: 47, min: 96, max: 600, collapseBelow: below) == .collapse)
        #expect(PaneResize.resolve(proposed: -10, min: 96, max: 600, collapseBelow: below) == .collapse)
        #expect(PaneResize.resolve(proposed: 48, min: 96, max: 600, collapseBelow: below) == .size(96))
        #expect(PaneResize.resolve(proposed: 200, min: 96, max: 600, collapseBelow: below) == .size(200))
    }
}
