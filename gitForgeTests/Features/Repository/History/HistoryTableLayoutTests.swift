import Foundation
import Testing
@testable import gitForge

@Suite("HistoryTableLayout")
struct HistoryTableLayoutTests {

    private let chrome = 2 * HistoryTableLayout.rowInset + HistoryTableLayout.leadingPadding
        + HistoryTableLayout.trailingPadding

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
        #expect(!narrow.authorFits)
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
        #expect(layout.fixedWidth == 400 + chrome + 4 * HistoryTableLayout.gap)
    }

    // MARK: Handles follow the pointer (audit H1)

    @Test("Widening a column after Description moves its leading edge, where its handle sits, by as much")
    func leadingEdgeTracksWidth() {
        // Leading edge of Author: the end of Description (graph, its gap and
        // Description from the row's start).
        func authorLeadingEdge(_ layout: HistoryTableLayout) -> CGFloat {
            HistoryTableLayout.rowInset + HistoryTableLayout.leadingPadding
                + layout.graph + HistoryTableLayout.gap + layout.description
        }
        let before = HistoryTableLayout(viewport: 1000, graph: 80, author: 112, date: 92, commit: 64)
        let after = HistoryTableLayout(viewport: 1000, graph: 80, author: 152, date: 92, commit: 64)
        #expect(authorLeadingEdge(before) - authorLeadingEdge(after) == 40)
        // The trailing edge, where the handle used to sit, doesn't move.
        #expect(authorLeadingEdge(before) + before.author == authorLeadingEdge(after) + after.author)
    }

    @Test("A column grows only by what Description can give, and never past its cap")
    func handleMax() {
        #expect(CommitTableHeader.handleMax(width: 100, min: 50, slack: 30, cap: 280) == 130)
        #expect(CommitTableHeader.handleMax(width: 100, min: 50, slack: 500, cap: 280) == 280)
        // Description already at its floor: the column can't grow, nor go under its minimum.
        #expect(CommitTableHeader.handleMax(width: 40, min: 50, slack: 0, cap: 280) == 50)
        let layout = HistoryTableLayout(viewport: 900, graph: 80, author: 112, date: 92, commit: 64)
        #expect(layout.descriptionSlack == layout.description - HistoryTableLayout.minDescription)
    }

    // MARK: Hidden columns (audit M4)

    @Test("A hidden column takes no width and no gap; Description takes the room")
    func hiddenColumn() {
        let all = HistoryTableLayout(viewport: 1000, graph: 80, author: 112, date: 92, commit: 64)
        let noDate = HistoryTableLayout(viewport: 1000, graph: 80, author: 112, date: 92, commit: 64,
                                        hidden: [.date])
        #expect(!noDate.showsDate)
        #expect(noDate.date == 0)
        #expect(noDate.description == all.description + 92 + HistoryTableLayout.gap)
        #expect(noDate.totalWidth == 1000)
    }

    @Test("With every optional column hidden, Description fills the row")
    func onlyDescription() {
        let layout = HistoryTableLayout(viewport: 700, graph: 80, author: 112, date: 92, commit: 64,
                                        hidden: Set(HistoryTableLayout.Column.allCases))
        #expect(!layout.showsGraph && !layout.showsAuthor && !layout.showsDate && !layout.showsCommit)
        #expect(layout.fixedWidth == chrome)
        #expect(layout.description == 700 - chrome)
    }

    @Test("Hiding other columns can make room for Author")
    func hidingMakesRoomForAuthor() {
        let narrow = HistoryTableLayout(viewport: 540, graph: 80, author: 112, date: 92, commit: 64)
        #expect(!narrow.showsAuthor)
        let noGraph = HistoryTableLayout(viewport: 540, graph: 80, author: 112, date: 92, commit: 64,
                                         hidden: [.graph], authorFitted: true)
        #expect(noGraph.showsAuthor)
    }

    // MARK: Author hysteresis (audit M3)

    @Test("An Author that didn't fit comes back only with room to spare")
    func authorReturnMargin() {
        // Description with Author would be exactly its floor plus 10.
        let fixedWithAuthor = chrome + 4 * HistoryTableLayout.gap + 80 + 112 + 92 + 64
        let viewport = fixedWithAuthor + HistoryTableLayout.minDescription + 10
        let wasShown = HistoryTableLayout(viewport: viewport, graph: 80, author: 112, date: 92, commit: 64,
                                          authorFitted: true)
        #expect(wasShown.showsAuthor)
        let wasHidden = HistoryTableLayout(viewport: viewport, graph: 80, author: 112, date: 92, commit: 64,
                                           authorFitted: false)
        #expect(!wasHidden.showsAuthor)
        let roomy = HistoryTableLayout(viewport: viewport + HistoryTableLayout.authorReturnMargin, graph: 80,
                                       author: 112, date: 92, commit: 64, authorFitted: false)
        #expect(roomy.showsAuthor)
    }

    @Test("While the user hides Author, its fit carries over unchanged")
    func authorFitCarriesOverWhileHidden() {
        let fitted = HistoryTableLayout(viewport: 400, graph: 80, author: 112, date: 92, commit: 64,
                                        hidden: [.author], authorFitted: true)
        #expect(!fitted.showsAuthor)
        #expect(fitted.authorFits)
        let unfitted = HistoryTableLayout(viewport: 2000, graph: 80, author: 112, date: 92, commit: 64,
                                          hidden: [.author], authorFitted: false)
        #expect(!unfitted.authorFits)
    }

    // MARK: Graph width (audit H4)

    @Test("Until dragged, the graph fits its lanes, up to a share of the table")
    func autoGraphWidth() {
        // Few lanes: their width, over the column's own minimum.
        #expect(CommitGraphTable.autoGraphWidth(lanesWidth: 140, viewport: 900, columnMin: 110) == 140)
        // Single lane: the column minimum.
        #expect(CommitGraphTable.autoGraphWidth(lanesWidth: 24, viewport: 900, columnMin: 110) == 110)
        // Many lanes in a narrow table: capped, so Description keeps its room.
        let capped = CommitGraphTable.autoGraphWidth(lanesWidth: 400, viewport: 800, columnMin: 110)
        #expect(capped == 800 * CommitGraphTable.maxAutomaticGraphShare)
        let full = HistoryTableLayout(viewport: 800, graph: 400, author: 112, date: 92, commit: 64)
        let layout = HistoryTableLayout(viewport: 800, graph: capped, author: 112, date: 92, commit: 64)
        #expect(full.totalWidth > 800)
        #expect(layout.totalWidth == 800)
    }

    @Test("Once dragged, the user's width wins over the lanes, never under the column minimum")
    func userGraphWidth() {
        // Narrower than the lanes need: kept (the lanes clip).
        #expect(CommitGraphTable.graphWidth(isAuto: false, userWidth: 70, lanesWidth: 300,
                                            viewport: 1000, columnMin: 60) == 70)
        // Wider than the auto cap: kept too.
        #expect(CommitGraphTable.graphWidth(isAuto: false, userWidth: 500, lanesWidth: 300,
                                            viewport: 1000, columnMin: 60) == 500)
        #expect(CommitGraphTable.graphWidth(isAuto: false, userWidth: 20, lanesWidth: 300,
                                            viewport: 1000, columnMin: 60) == 60)
        // Auto ignores the stored width.
        #expect(CommitGraphTable.graphWidth(isAuto: true, userWidth: 70, lanesWidth: 300,
                                            viewport: 1000, columnMin: 60) == 300)
    }
}
