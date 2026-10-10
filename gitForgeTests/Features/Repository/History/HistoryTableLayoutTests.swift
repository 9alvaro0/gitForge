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

    @Test("A narrow viewport keeps Description at its minimum and the table scrolls")
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
}
