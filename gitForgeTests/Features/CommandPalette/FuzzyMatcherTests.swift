import Foundation
import Testing
@testable import gitForge

@Suite("FuzzyMatcher")
struct FuzzyMatcherTests {

    @Test("Letters in order match, and the shorter text scores higher")
    func inOrder() throws {
        let checkout = try #require(FuzzyMatcher.match("che", in: "Checkout branch…"))
        let cherry = try #require(FuzzyMatcher.match("che", in: "Cherry-pick 3f6a2bb onto HEAD"))
        #expect(checkout.indices == [0, 1, 2])
        #expect(cherry.indices == [0, 1, 2])
        #expect(checkout.score > cherry.score)
    }

    @Test("Letters out of order don't match")
    func outOfOrder() {
        #expect(FuzzyMatcher.match("kc", in: "Checkout") == nil)
    }

    @Test("Case and accents are ignored")
    func folding() {
        #expect(FuzzyMatcher.match("CAFE", in: "Café") != nil)
        #expect(FuzzyMatcher.match("cafe", in: "Café")?.indices == [0, 1, 2, 3])
    }

    @Test("Word starts and consecutive letters score higher")
    func scoring() throws {
        let wordStart = try #require(FuzzyMatcher.match("cl", in: "Cache LaneLayout"))
        let inside = try #require(FuzzyMatcher.match("cl", in: "an uncle"))
        #expect(wordStart.score > inside.score)
        let together = try #require(FuzzyMatcher.match("pus", in: "push now"))
        let apart = try #require(FuzzyMatcher.match("pus", in: "pull use"))
        #expect(together.score > apart.score)
    }

    @Test("An empty or blank query matches everything with no letters; one longer than the text matches nothing")
    func edges() {
        #expect(FuzzyMatcher.match("", in: "Fetch") == FuzzyMatch(score: 0, indices: []))
        #expect(FuzzyMatcher.match("   ", in: "Fetch") == FuzzyMatch(score: 0, indices: []))
        #expect(FuzzyMatcher.match("fetching", in: "Fetch") == nil)
    }

    @Test("Emoji and combining marks count as one character each, so highlights land on the right letters")
    func graphemes() throws {
        // "e" + U+0301: one character, folded to "e".
        #expect(FuzzyMatcher.match("cafe", in: "Cafe\u{301} bar")?.indices == [0, 1, 2, 3])
        #expect(FuzzyMatcher.match("dep", in: "🚀 Deploy main")?.indices == [2, 3, 4])
        #expect(FuzzyMatcher.match("🚀d", in: "🚀 Deploy")?.indices == [0, 2])
        #expect(FuzzyMatcher.match("x", in: "👩‍👩‍👧 family") == nil)
    }
}
