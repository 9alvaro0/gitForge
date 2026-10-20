import Testing
@testable import gitForge

@Suite("ListKeyboardNavigation — ↑↓ target row")
@MainActor
struct ListKeyboardNavigationTests {
    private typealias Nav = ListKeyboardNavigation<String>
    private let ids = ["a", "b", "c"]

    @Test("Empty list → nil, so the key event stays unhandled")
    func emptyList() {
        #expect(Nav.target(in: [], from: nil, by: 1) == nil)
        #expect(Nav.target(in: [], from: "a", by: -1) == nil)
    }

    @Test("No selection → first row, whichever the direction")
    func noSelection() {
        #expect(Nav.target(in: ids, from: nil, by: 1) == "a")
        #expect(Nav.target(in: ids, from: nil, by: -1) == "a")
    }

    @Test("Selection gone from the list → first row")
    func staleSelection() {
        #expect(Nav.target(in: ids, from: "zzz", by: 1) == "a")
    }

    @Test("Down / up move one row")
    func moves() {
        #expect(Nav.target(in: ids, from: "a", by: 1) == "b")
        #expect(Nav.target(in: ids, from: "c", by: -1) == "b")
    }

    @Test("Clamps at both ends, no wrap")
    func clamps() {
        #expect(Nav.target(in: ids, from: "c", by: 1) == "c")
        #expect(Nav.target(in: ids, from: "a", by: -1) == "a")
    }

    @Test("Working-copy rows: the same path on both sides are distinct stops")
    func workingCopyRows() {
        let rows = [
            WorkingCopyRowID(side: .unstaged, path: "x"),
            WorkingCopyRowID(side: .staged, path: "x"),
        ]
        #expect(ListKeyboardNavigation<WorkingCopyRowID>.target(in: rows, from: rows[0], by: 1) == rows[1])
    }
}
