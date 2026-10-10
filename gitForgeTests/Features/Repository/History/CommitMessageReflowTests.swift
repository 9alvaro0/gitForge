import Foundation
import Testing
@testable import gitForge

@Suite("Commit message reflow")
struct CommitMessageReflowTests {

    @Test("Hard-wrapped lines of a paragraph join with a space")
    func joinsParagraph() {
        #expect(CommitMessage.reflow("GraphColumnView draws with LaneColors (HEAD lane in the\naccent, trunks pinned).")
                == "GraphColumnView draws with LaneColors (HEAD lane in the accent, trunks pinned).")
    }

    @Test("Blank lines keep paragraphs apart")
    func keepsParagraphs() {
        #expect(CommitMessage.reflow("First one\nwraps here.\n\nSecond one.") == "First one wraps here.\n\nSecond one.")
    }

    @Test("List items and indented lines stay on their own lines")
    func keepsListsAndCode() {
        let message = "Changes:\n- one item\n  continued\n* another\n1. numbered\n    let x = 1\nTrailer-Line: value"
        #expect(CommitMessage.reflow(message) == "Changes:\n- one item continued\n* another\n1. numbered\n    let x = 1\nTrailer-Line: value")
    }

    @Test("Trailers like Co-authored-by and Refs keep their own lines")
    func keepsTrailers() {
        #expect(CommitMessage.reflow("Body text.\n\nRefs #187\nCo-authored-by: Marc <m@p.dev>")
                == "Body text.\n\nRefs #187\nCo-authored-by: Marc <m@p.dev>")
    }
}
