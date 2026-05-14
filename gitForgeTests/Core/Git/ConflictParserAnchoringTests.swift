import Foundation
import Testing
@testable import gitForge

/// Marker-anchoring regressions. Without column-0 anchoring, a source-code
/// comment containing `<<<<<<<` is misread as the start of a conflict and
/// the parser absorbs everything up to the next `>>>>>>>` into a corrupt
/// hunk that gets written back to disk on resolve.
@Suite("ConflictParser — marker anchoring")
struct ConflictParserAnchoringTests {

    @Test("Indented `<<<<<<<` (inside a comment) is NOT treated as a conflict start")
    func indentedOursMarkerIgnored() {
        let content = """
        line before
        // <<<<<<< TODO resolve before merging
        line after
        """
        let result = ConflictParser.parse(content)
        #expect(result.hunks.isEmpty)
        // The pseudo-marker must remain as plain text — re-emit via apply()
        // and check the file is unchanged.
        let resolved = ConflictParser.apply(content: content, picks: [:], hunks: result.hunks)
        #expect(resolved == content)
    }

    @Test("`<<<<<<<` with trailing non-space char is NOT a marker")
    func nonSpaceAfterMarkerIgnored() {
        // git always emits "<<<<<<<" alone or followed by a space+label.
        // "<<<<<<<X" is content, not a marker.
        let content = """
        a
        <<<<<<<X
        b
        """
        let result = ConflictParser.parse(content)
        #expect(result.hunks.isEmpty)
    }

    @Test("Bare `<<<<<<<` (no label) is still recognised as a marker")
    func bareMarkerRecognised() {
        let content = """
        a
        <<<<<<<
        ours-line
        =======
        theirs-line
        >>>>>>>
        b
        """
        let result = ConflictParser.parse(content)
        #expect(result.hunks.count == 1)
        #expect(result.hunks.first?.ours == ["ours-line"])
        #expect(result.hunks.first?.theirs == ["theirs-line"])
    }

    @Test("Comment containing `// <<<<<<<` BEFORE a real conflict doesn't merge the two")
    func commentBeforeRealConflict() {
        // This is the regression case: a leading false-positive previously
        // ate the real conflict markers below it, producing a hunk whose
        // `ours` contained both the comment and the real `=======` line.
        let content = """
        // <<<<<<< something in a comment
        ok-line
        <<<<<<< HEAD
        real-ours
        =======
        real-theirs
        >>>>>>> branch
        end
        """
        let result = ConflictParser.parse(content)
        #expect(result.hunks.count == 1)
        #expect(result.hunks.first?.ours == ["real-ours"])
        #expect(result.hunks.first?.theirs == ["real-theirs"])
    }

    @Test("Indented `>>>>>>>` (in content) is NOT taken as conflict end")
    func indentedTheirsMarkerIgnored() {
        // The closing marker must also be column-0 anchored — otherwise a
        // comment inside `theirs` ends the conflict prematurely.
        let content = """
        <<<<<<< HEAD
        ours-a
        =======
        theirs-a
        // >>>>>>> NOT a marker
        theirs-b
        >>>>>>> branch
        """
        let result = ConflictParser.parse(content)
        #expect(result.hunks.count == 1)
        #expect(result.hunks.first?.theirs == [
            "theirs-a",
            "// >>>>>>> NOT a marker",
            "theirs-b",
        ])
    }

    @Test("Markers with non-space suffix in the closing marker also ignored")
    func nonSpaceAfterTheirsMarker() {
        let content = """
        <<<<<<< HEAD
        ours
        =======
        theirs
        >>>>>>>X
        """
        // Unterminated → parseConflict returns nil → first marker stays as
        // plain text in buffer.
        let result = ConflictParser.parse(content)
        #expect(result.hunks.isEmpty)
    }
}
