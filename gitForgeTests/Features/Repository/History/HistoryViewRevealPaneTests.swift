import Foundation
import Testing
@testable import gitForge

@Suite("HistoryView.revealedDiffPaneHeight")
@MainActor
struct HistoryViewRevealPaneTests {

    private let threshold: CGFloat = 80
    private let defaultHeight: CGFloat = 280

    @Test("Zero height bumps up to the default")
    func zeroBumps() {
        let out = HistoryView.revealedDiffPaneHeight(
            current: 0, threshold: threshold, defaultHeight: defaultHeight
        )
        #expect(out == defaultHeight)
    }

    @Test("A sliver below the threshold bumps up to the default")
    func sliverBumps() {
        let out = HistoryView.revealedDiffPaneHeight(
            current: 40, threshold: threshold, defaultHeight: defaultHeight
        )
        #expect(out == defaultHeight)
    }

    @Test("A height at the threshold is treated as visible and stays put")
    func atThresholdStays() {
        let out = HistoryView.revealedDiffPaneHeight(
            current: threshold, threshold: threshold, defaultHeight: defaultHeight
        )
        #expect(out == threshold)
    }

    @Test("A taller height than the default keeps the user's chosen size")
    func tallerStays() {
        let out = HistoryView.revealedDiffPaneHeight(
            current: 600, threshold: threshold, defaultHeight: defaultHeight
        )
        #expect(out == 600)
    }
}
