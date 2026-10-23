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

    @Test("An item without keywords matches its label as before")
    func labelOnly() {
        #expect(PaletteSearch.match("fx", label: "feature/x", keywords: [], number: nil)
                == FuzzyMatcher.match("fx", in: "feature/x"))
    }
}
