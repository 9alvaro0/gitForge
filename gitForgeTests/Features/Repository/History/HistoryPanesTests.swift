import Foundation
import Testing
@testable import gitForge

@Suite("History panes")
struct HistoryPanesTests {

    // MARK: Inspector width

    @Test("The inspector leaves the table its minimum, within its own bounds")
    func inspectorCap() {
        let handle = HistorySplitMetrics.handleWidth
        let roomy = 2000 as CGFloat
        #expect(HistorySplitMetrics.inspectorCap(available: roomy) == HistorySplitMetrics.maxInspectorWidth)
        let tight = HistorySplitMetrics.minTableWidth + handle + 400
        #expect(HistorySplitMetrics.inspectorCap(available: tight) == 400)
        #expect(HistorySplitMetrics.inspectorCap(available: 600) == HistorySplitMetrics.minInspectorWidth)
    }

    // MARK: Diff height (audit H3)

    @Test("The diff never takes the detail's minimum or more than the inspector has")
    func diffHeightCap() {
        let cap = HistoryInspectorMetrics.diffHeightCap(available: 700)
        #expect(cap == 700 - HistoryInspectorMetrics.handleHeight - HistoryInspectorMetrics.minDetailHeight)
        // A short inspector still shows a sliver of diff.
        #expect(HistoryInspectorMetrics.diffHeightCap(available: 100) == HistoryInspectorMetrics.minDiffHeight)
    }

    @Test("A sliver of diff grows back to the default on a new selection")
    func sliverBumps() {
        #expect(HistoryInspectorMetrics.revealedDiffHeight(current: 0) == HistoryInspectorMetrics.defaultDiffHeight)
        #expect(HistoryInspectorMetrics.revealedDiffHeight(current: 40) == HistoryInspectorMetrics.defaultDiffHeight)
    }

    @Test("A readable diff keeps the user's height")
    func readableStays() {
        let threshold = HistoryInspectorMetrics.sliverHeight
        #expect(HistoryInspectorMetrics.revealedDiffHeight(current: threshold) == threshold)
        #expect(HistoryInspectorMetrics.revealedDiffHeight(current: 600) == 600)
    }

    @Test("Stored sizes fall back to the defaults and stay within bounds")
    func storedSizes() throws {
        let suite = "tests.historyPanes.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        #expect(HistoryInspectorMetrics.storedDiffHeight(defaults) == HistoryInspectorMetrics.defaultDiffHeight)
        #expect(HistorySplitMetrics.storedInspectorWidth(defaults) == HistorySplitMetrics.defaultInspectorWidth)
        defaults.set(420.0, forKey: HistoryInspectorMetrics.heightKey)
        defaults.set(5000.0, forKey: HistorySplitMetrics.widthKey)
        #expect(HistoryInspectorMetrics.storedDiffHeight(defaults) == 420)
        #expect(HistorySplitMetrics.storedInspectorWidth(defaults) == HistorySplitMetrics.maxInspectorWidth)
    }

    // MARK: Expanded diff's file navigation

    @Test("Stepping moves through the files and stops at either end")
    func neighbor() {
        let files = ["a", "b", "c"]
        #expect(DiffFileNavigation.neighbor(of: "b", in: files, offset: 1) == "c")
        #expect(DiffFileNavigation.neighbor(of: "b", in: files, offset: -1) == "a")
        #expect(DiffFileNavigation.neighbor(of: "c", in: files, offset: 1) == nil)
        #expect(DiffFileNavigation.neighbor(of: "a", in: files, offset: -1) == nil)
    }

    @Test("With no file open (or one that's gone), next opens the first")
    func neighborWithoutCurrent() {
        let files = ["a", "b"]
        #expect(DiffFileNavigation.neighbor(of: nil, in: files, offset: 1) == "a")
        #expect(DiffFileNavigation.neighbor(of: "gone", in: files, offset: 1) == "a")
        #expect(DiffFileNavigation.neighbor(of: nil, in: files, offset: -1) == nil)
        #expect(DiffFileNavigation.neighbor(of: nil, in: [], offset: 1) == nil)
    }

    @Test("Position reads as index and count of the open file")
    func position() {
        let files = ["a", "b", "c"]
        let position = DiffFileNavigation.position(of: "b", in: files)
        #expect(position?.index == 1)
        #expect(position?.count == 3)
        #expect(DiffFileNavigation.position(of: nil, in: files) == nil)
        #expect(DiffFileNavigation.position(of: "z", in: files) == nil)
    }
}
