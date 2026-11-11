import Foundation
import Testing
@testable import gitForge

@Suite("AuthorMonogram — initials and colour")
struct AuthorMonogramTests {

    @Test("Initials: first letter of the first two words",
          arguments: [
            ("Ana Pérez", "AP"),
            ("ana pérez garcía", "AP"),
            ("M. Vélez", "MV"),
            ("Ana", "A"),
            ("  Luis   Gómez ", "LG"),
            ("Ángel Ñúñez", "ÁÑ"),
            ("— Ana", "A"),
            ("dependabot[bot]", "D"),
            ("李 小龙", "李小"),
          ])
    func initials(name: String, expected: String) {
        #expect(AuthorMonogram.initials(name: name, email: "x@forge.dev") == expected)
    }

    @Test("Without a name, the email's first letter; with nothing, a question mark")
    func fallbacks() {
        #expect(AuthorMonogram.initials(name: "", email: "lucia@forge.dev") == "L")
        #expect(AuthorMonogram.initials(name: "   ", email: "_ci@forge.dev") == "C")
        #expect(AuthorMonogram.initials(name: "", email: "") == "?")
        #expect(AuthorMonogram.initials(name: "—", email: "") == "?")
    }

    @Test("The colour keys on the email, whatever its case or spacing")
    func colourSeed() {
        let a = AuthorMonogram.colorSeed(name: "Ana", email: " Ana@Forge.dev ")
        let b = AuthorMonogram.colorSeed(name: "Ana P.", email: "ana@forge.dev")
        #expect(a == b)
        #expect(AuthorMonogram.paletteIndex(seed: a, count: 6) == AuthorMonogram.paletteIndex(seed: b, count: 6))
        #expect(AuthorMonogram.colorSeed(name: "Ana", email: "") == "Ana")
    }

    @Test("The palette index is stable across runs and always in range")
    func paletteIndex() {
        // Pinned: a seeded hash (Swift's `hashValue`) would change per process.
        #expect(AuthorMonogram.paletteIndex(seed: "lucia@forge.dev", count: 6) == AuthorMonogram.paletteIndex(seed: "lucia@forge.dev", count: 6))
        #expect(AuthorMonogram.paletteIndex(seed: "ab", count: 6) == Int((97 * 31 + 98) % 6))
        for seed in ["", "a", String(repeating: "z", count: 500)] {
            #expect((0..<6).contains(AuthorMonogram.paletteIndex(seed: seed, count: 6)))
        }
        #expect(AuthorMonogram.paletteIndex(hash: .min, count: 6) >= 0)
        #expect(AuthorMonogram.paletteIndex(seed: "a", count: 0) == 0)
    }

    @Test("CommitAuthor: normalized email and spoken name")
    func commitAuthor() {
        let author = CommitAuthor(name: "  ", email: " Ana@Forge.DEV")
        #expect(author.normalizedEmail == "ana@forge.dev")
        #expect(author.displayName == " Ana@Forge.DEV")
        #expect(CommitAuthor(name: "Ana", email: "a@b").displayName == "Ana")
    }
}
