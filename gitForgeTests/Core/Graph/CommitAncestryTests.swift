import Foundation
import Testing
@testable import gitForge

@Suite("CommitAncestry")
struct CommitAncestryTests {

    private static func commit(_ sha: String, _ parents: [String] = []) -> Commit {
        Commit(sha: sha, parentShas: parents, authorName: "T", authorEmail: "t@x",
               authorDate: .init(timeIntervalSince1970: 0), subject: sha)
    }

    /// main: a ← b ← m (merge of b and f); feature: a ← f; other: a ← o.
    private static let log = [
        commit("m", ["b", "f"]), commit("o", ["a"]), commit("f", ["a"]),
        commit("b", ["a"]), commit("a"),
    ]

    @Test("A tip reaches its whole history, merges included")
    func mergeTip() {
        #expect(CommitAncestry.reachable(from: "m", in: Self.log) == ["m", "b", "f", "a"])
    }

    @Test("A side branch reaches only its own line")
    func sideBranch() {
        #expect(CommitAncestry.reachable(from: "o", in: Self.log) == ["o", "a"])
    }

    @Test("Unloaded parents stop the walk; an unknown tip reaches nothing")
    func partial() {
        let page = [Self.commit("c", ["b"]), Self.commit("b", ["a"])]
        #expect(CommitAncestry.reachable(from: "c", in: page) == ["c", "b"])
        #expect(CommitAncestry.reachable(from: "zzz", in: page).isEmpty)
    }
}
