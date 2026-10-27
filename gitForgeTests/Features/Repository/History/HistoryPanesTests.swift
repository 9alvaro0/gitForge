import Foundation
import Testing
@testable import gitForge

@Suite("History panes")
struct HistoryPanesTests {

    // MARK: Inspector width

    @Test("The inspector may take whatever leaves the table its minimum (audit B2)")
    func inspectorCap() {
        let handle = HistorySplitMetrics.handleWidth
        let table = HistorySplitMetrics.minTableWidth
        // No fixed ceiling: a wide window gives the inspector the room.
        #expect(HistorySplitMetrics.inspectorCap(available: 2560) == 2560 - table - handle)
        #expect(HistorySplitMetrics.inspectorCap(available: table + handle + 400) == 400)
    }

    @Test("A cramped window still gets an inspector at its minimum")
    func inspectorCapFloor() {
        #expect(HistorySplitMetrics.inspectorCap(available: 600) == HistorySplitMetrics.minInspectorWidth)
    }

    @Test("The inspector shows until hidden, and the choice is kept")
    func inspectorVisibility() throws {
        let suite = "tests.historyPanes.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        #expect(HistorySplitMetrics.storedInspectorVisible(defaults))
        HistorySplitMetrics.storeInspectorVisible(false, defaults)
        #expect(!HistorySplitMetrics.storedInspectorVisible(defaults))
        // Same key as the old collapsed strip, so an earlier choice carries over.
        #expect(defaults.bool(forKey: HistorySplitMetrics.collapsedKey))
        HistorySplitMetrics.storeInspectorVisible(true, defaults)
        #expect(HistorySplitMetrics.storedInspectorVisible(defaults))
    }

    // MARK: Diff height (audit H3)

    @Test("The diff never takes the detail's minimum or more than the inspector has")
    func diffHeightCap() {
        let cap = HistoryInspectorMetrics.diffHeightCap(available: 700)
        #expect(cap == 700 - HistoryInspectorMetrics.handleHeight - HistoryInspectorMetrics.minDetailHeight)
        // A short inspector still shows a sliver of diff.
        #expect(HistoryInspectorMetrics.diffHeightCap(available: 100) == HistoryInspectorMetrics.minDiffHeight)
    }

    @Test("The diff collapses when dragged under half its minimum, so it is never a sliver (audit B3)")
    func diffCollapsePoint() {
        let min = HistoryInspectorMetrics.minDiffHeight
        let below = PaneResize.collapseThreshold(min: min)
        #expect(PaneResize.resolve(proposed: below - 1, min: min, max: 600, collapseBelow: below) == .collapse)
        #expect(PaneResize.resolve(proposed: below + 1, min: min, max: 600, collapseBelow: below) == .size(min))
    }

    @Test("Stored sizes fall back to the defaults and keep their minimums")
    func storedSizes() throws {
        let suite = "tests.historyPanes.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        #expect(HistoryInspectorMetrics.storedDiffHeight(defaults) == HistoryInspectorMetrics.defaultDiffHeight)
        #expect(HistorySplitMetrics.storedInspectorWidth(defaults) == HistorySplitMetrics.defaultInspectorWidth)
        defaults.set(420.0, forKey: HistoryInspectorMetrics.heightKey)
        defaults.set(1400.0, forKey: HistorySplitMetrics.widthKey)
        #expect(HistoryInspectorMetrics.storedDiffHeight(defaults) == 420)
        // Kept for a wide window; the cap applies when shown.
        #expect(HistorySplitMetrics.storedInspectorWidth(defaults) == 1400)
    }

    @Test("A sliver saved before the minimum grew comes back at the minimum")
    func storedSliver() throws {
        let suite = "tests.historyPanes.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        defaults.set(36.0, forKey: HistoryInspectorMetrics.heightKey)
        defaults.set(100.0, forKey: HistorySplitMetrics.widthKey)
        #expect(HistoryInspectorMetrics.storedDiffHeight(defaults) == HistoryInspectorMetrics.minDiffHeight)
        #expect(HistorySplitMetrics.storedInspectorWidth(defaults) == HistorySplitMetrics.minInspectorWidth)
    }

    // MARK: Commit detail sections (audit M5)

    @Test("Unfolded details take at most a share of the commit detail, never less than a few lines")
    func detailsCap() {
        #expect(HistoryInspectorMetrics.detailsCap(columnHeight: 500) == 500 * HistoryInspectorMetrics.detailsShare)
        #expect(HistoryInspectorMetrics.detailsCap(columnHeight: 100) == HistoryInspectorMetrics.minDetailsHeight)
        #expect(HistoryInspectorMetrics.detailsCap(columnHeight: 0) == HistoryInspectorMetrics.minDetailsHeight)
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
