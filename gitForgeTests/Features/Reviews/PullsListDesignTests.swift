import Foundation
import Testing
@testable import gitForge

@Suite("Pull requests list — folding, marks and cards")
@MainActor
struct PullsListDesignTests {
    @Test("Folded repos: read from their saved lines, toggled, unfolded, saved sorted")
    func collapsedRepos() {
        var repos = CollapsedRepos(raw: "")
        #expect(repos.keys.isEmpty)
        repos.toggle("b.test/x/y")
        repos.toggle("a.test/p/q")
        #expect(repos.contains("a.test/p/q") && repos.contains("b.test/x/y"))
        #expect(repos.raw == "a.test/p/q\nb.test/x/y")
        repos.toggle("b.test/x/y")
        #expect(!repos.contains("b.test/x/y"))
        // Out of `#expect`: the macro can't call a mutating method.
        let unfolded = repos.expand("a.test/p/q")
        let again = repos.expand("a.test/p/q")
        #expect(unfolded)
        #expect(!again)
        #expect(repos.raw.isEmpty)
        #expect(CollapsedRepos(raw: "a\n\nb\n").keys == ["a", "b"])
    }

    @Test("A repo's initials: one letter per word, two at most")
    func initials() {
        #expect(RepoMonogram.initials(for: "payments-app") == "PA")
        #expect(RepoMonogram.initials(for: "activo2-front-ios") == "AF")
        #expect(RepoMonogram.initials(for: "ledger") == "L")
        #expect(RepoMonogram.initials(for: "r2_d2.swift") == "RD")
        #expect(RepoMonogram.initials(for: "---") == "?")
    }

    @Test("A repo keeps its colour: the same key, the same lane")
    func monogramLane() {
        let keys = (0..<40).map { "gitlab.example.test/group/repo-\($0)" }
        #expect(keys.map(RepoMonogram.lane(for:)) == keys.map(RepoMonogram.lane(for:)))
        // Spread over more than one colour.
        #expect(Set(keys.map(RepoMonogram.lane(for:))).count > 3)
    }

    @Test("Rows in a card: the first and last round its corners, one alone rounds all four")
    func placement() {
        #expect(ReviewsList.placement(0, of: 1) == .only)
        #expect((0..<3).map { ReviewsList.placement($0, of: 3) } == [.first, .middle, .last])
        #expect((0..<2).map { ReviewsList.placement($0, of: 2) } == [.first, .last])
    }
}
