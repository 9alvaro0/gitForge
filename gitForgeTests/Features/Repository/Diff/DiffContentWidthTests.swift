import AppKit
import Testing
@testable import gitForge

@Suite("DiffContentWidth — width of the widest diff line")
@MainActor
struct DiffContentWidthTests {
    private let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    @Test("Columns: tabs a full stop, wide characters two")
    func columns() {
        #expect(DiffContentWidth.estimatedColumns("abc") == 3)
        #expect(DiffContentWidth.estimatedColumns("\tx") == 9)
        #expect(DiffContentWidth.estimatedColumns("日本") == 4)
        #expect(DiffContentWidth.estimatedColumns("") == 0)
    }

    @Test("Keeps the widest lines, widest first")
    func candidates() {
        let lines = ["a", "abcd", "ab", "abc"]
        #expect(DiffContentWidth.widestCandidates(lines, limit: 2) == ["abcd", "abc"])
        #expect(DiffContentWidth.widestCandidates(lines, limit: 10) == ["abcd", "abc", "ab", "a"])
        #expect(DiffContentWidth.widestCandidates([], limit: 4).isEmpty)
    }

    @Test("A long line deep in a big diff is still found")
    func longLineFarDown() {
        var lines = Array(repeating: "short line", count: 10_000)
        let long = String(repeating: "x", count: 500)
        lines[9_000] = long
        #expect(DiffContentWidth.widestCandidates(lines, limit: 4).first == long)
    }

    @Test("Row width covers the code plus the gutters")
    func rowWidth() {
        let line = String(repeating: "x", count: 300)
        let code = NSAttributedString(string: line, attributes: [.font: font]).size().width
        let width = DiffContentWidth.unifiedRowWidth(of: [line], font: font)
        #expect(width >= code + DiffContentWidth.unifiedChrome)
        #expect(DiffContentWidth.unifiedRowWidth(of: [], font: font) == 0)
    }
}
