import Foundation
import Testing
@testable import gitForge

@Suite("Palette search")
struct PaletteSearchTests {
    static func match(_ query: String, number: Int? = 482) -> FuzzyMatch? {
        PaletteSearch.match(query, label: "Retry on timeout",
                            keywords: ["apps/payments/backend/ledger", "fix/PAY-12-retry", "marta", "Marta Ruiz", "482"],
                            number: number)
    }

    @Test("A query that is only a number, with # or ! or neither", arguments: ["482", "#482", "!482", " 482 "])
    func exactNumber(query: String) {
        #expect(PaletteSearch.number(in: query) == 482)
        #expect(Self.match(query)?.score == PaletteSearch.exactNumberScore)
        #expect(Self.match(query)?.indices == [])
    }

    @Test("Not a number", arguments: ["48a", "#", "!-1", "4 82", "#0"])
    func notANumber(query: String) {
        #expect(PaletteSearch.number(in: query) == nil)
    }

    @Test("Title, repo path, branch, login and name each find it", arguments: ["timeout", "ledger", "PAY-12", "marta", "Ruiz"])
    func fields(query: String) {
        #expect(Self.match(query) != nil)
    }

    @Test("Words match in any order; only the title's letters are highlighted")
    func words() throws {
        let match = try #require(Self.match("ledger retry"))
        #expect(match.indices == [0, 1, 2, 3, 4])
        #expect(Self.match("retry ledger")?.score == match.score)
        #expect(Self.match("retry nope") == nil)
    }

    @Test("Part of the number still matches, below an exact one")
    func partialNumber() throws {
        let partial = try #require(Self.match("48"))
        #expect(partial.score < PaletteSearch.exactNumberScore)
    }

    // MARK: Contiguous words

    @Test("A word whose letters are only scattered in the title and keywords finds nothing")
    func scatteredLettersDontMatch() {
        let label = "feat(guides): add context to the notes"
        let keywords = ["acme/apps/notes", "feature/guides-context", "marta"]
        #expect(FuzzyMatcher.match("fix", in: label) != nil, "precondition: f, i and x are in the title, apart")
        #expect(PaletteSearch.match("fix", label: label, keywords: keywords, number: 31) == nil)
    }

    @Test("Case and accents are still ignored, and the title's run is highlighted")
    func foldingStillApplies() throws {
        let match = try #require(PaletteSearch.match("matriculas", label: "Valida las matrículas al guardar",
                                                     keywords: ["acme/apps/garage", "fix/plates"], number: 5))
        #expect(match.indices == Array(11...20))
        #expect(PaletteSearch.match("ACT2", label: "Retry the upload",
                                    keywords: ["acme/apps/garage", "feature/act2-upload"], number: 6) != nil)
    }

    @Test("Every word must appear unbroken somewhere, in any order")
    func everyWordContiguous() {
        let label = "Bump the snapshot library"
        let keywords = ["acme/apps/carousel/ios/carousel-front-ios", "chore/snapshot-bump", "marta"]
        #expect(PaletteSearch.match("snapshot marta", label: label, keywords: keywords, number: 13) != nil)
        #expect(PaletteSearch.match("marta snapshot", label: label, keywords: keywords, number: 13) != nil)
        #expect(FuzzyMatcher.match("bmp", in: label) != nil, "precondition: b, m and p are in the title, apart")
        #expect(PaletteSearch.match("snapshot bmp", label: label, keywords: keywords, number: 13) == nil)
    }

    @Test("A word at a word start in a short field scores above the same word inside a long one")
    func wordStartInShortFieldWins() throws {
        let short = try #require(PaletteSearch.match("carousel", label: "Fix the swipe threshold",
                                                     keywords: ["oss/carousel"], number: 1))
        let long = try #require(PaletteSearch.match("carousel", label: "Fix the swipe threshold",
                                                    keywords: ["acme/apps/minicarousel/ios/minicarousel-front-ios"], number: 1))
        #expect(short.score > long.score)
    }

    @Test("An item without keywords matches its label as before")
    func labelOnly() {
        #expect(PaletteSearch.match("fx", label: "feature/x", keywords: [], number: nil)
                == FuzzyMatcher.match("fx", in: "feature/x"))
    }
}
