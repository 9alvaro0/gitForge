import Foundation
import Testing
@testable import gitForge

@Suite("HistoryTableLayout")
struct HistoryTableLayoutTests {

    @Test("Description takes whatever the fixed columns leave, filling the viewport")
    func fills() {
        let layout = HistoryTableLayout(viewport: 900, graph: 80, author: 112, date: 92, commit: 64)
        #expect(layout.totalWidth == 900)
        #expect(layout.description == 900 - layout.fixedWidth)
    }

    @Test("When Description would drop below its floor, Author goes first")
    func hidesAuthor() {
        let wide = HistoryTableLayout(viewport: 900, graph: 80, author: 112, date: 92, commit: 64)
        #expect(wide.showsAuthor)
        let narrow = HistoryTableLayout(viewport: 520, graph: 80, author: 112, date: 92, commit: 64)
        #expect(!narrow.showsAuthor)
        #expect(narrow.author == 0)
        #expect(narrow.totalWidth == 520)
        #expect(narrow.description >= HistoryTableLayout.minDescription)
    }

    @Test("Below even that, Description holds its floor and the table scrolls")
    func floor() {
        let layout = HistoryTableLayout(viewport: 300, graph: 80, author: 112, date: 92, commit: 64)
        #expect(layout.description == HistoryTableLayout.minDescription)
        #expect(layout.totalWidth > 300)
    }

    @Test("Fixed width counts every column, gap and padding once")
    func fixedWidth() {
        let layout = HistoryTableLayout(viewport: 2000, graph: 100, author: 100, date: 100, commit: 100)
        let chrome = 2 * HistoryTableLayout.rowInset + HistoryTableLayout.leadingPadding
            + HistoryTableLayout.trailingPadding + 4 * HistoryTableLayout.gap
        #expect(layout.fixedWidth == 400 + chrome)
    }

    @Test("Lanes widen the graph column only up to a share of the table")
    func graphMinWidthCapped() {
        // Few lanes: their width, over the column's own minimum.
        #expect(CommitGraphTable.graphMinWidth(lanesWidth: 140, viewport: 900, columnMin: 110) == 140)
        // Single lane: the column minimum.
        #expect(CommitGraphTable.graphMinWidth(lanesWidth: 24, viewport: 900, columnMin: 110) == 110)
        // Many lanes in a narrow table: capped, so Description keeps its room.
        let capped = CommitGraphTable.graphMinWidth(lanesWidth: 400, viewport: 800, columnMin: 110)
        #expect(capped == 800 * CommitGraphTable.maxAutomaticGraphShare)
        let full = HistoryTableLayout(viewport: 800, graph: 400, author: 112, date: 92, commit: 64)
        let layout = HistoryTableLayout(viewport: 800, graph: capped, author: 112, date: 92, commit: 64)
        #expect(full.totalWidth > 800)
        #expect(layout.totalWidth == 800)
    }
}
