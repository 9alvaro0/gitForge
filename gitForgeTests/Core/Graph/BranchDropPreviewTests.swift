import Foundation
import Testing
@testable import gitForge

@Suite("BranchDropPreview")
struct BranchDropPreviewTests {

    private static func commit(_ sha: String, _ parents: [String] = []) -> Commit {
        Commit(sha: sha, parentShas: parents, authorName: "T", authorEmail: "t@x",
               authorDate: .init(timeIntervalSince1970: 0), subject: sha)
    }

    /// main: a ← b ← c; feature: a ← f1 ← f2 ← f3; orphan: z (no shared history).
    private static let log = [
        commit("c", ["b"]), commit("f3", ["f2"]), commit("f2", ["f1"]), commit("b", ["a"]),
        commit("f1", ["a"]), commit("a"), commit("z"),
    ]

    @Test("Branch on branch counts each side's own commits")
    func integrate() {
        #expect(BranchDropPreview.integrate(source: "f3", target: "c", in: Self.log)?.kind
                == .integrate(sourceOnly: 3, targetOnly: 2))
        // Target already contains the source's history: fast-forward shape.
        #expect(BranchDropPreview.integrate(source: "c", target: "b", in: Self.log)?.kind
                == .integrate(sourceOnly: 1, targetOnly: 0))
    }

    @Test("Branch on commit: back, forward, or onto another line")
    func move() {
        #expect(BranchDropPreview.move(from: "c", to: "a", in: Self.log)?.kind == .move(dropped: 2, gained: 0))
        #expect(BranchDropPreview.move(from: "a", to: "c", in: Self.log)?.kind == .move(dropped: 0, gained: 2))
        #expect(BranchDropPreview.move(from: "c", to: "f2", in: Self.log)?.kind == .move(dropped: 2, gained: 2))
    }

    @Test("No preview when a tip isn't loaded or the two share no loaded ancestor")
    func unknown() {
        #expect(BranchDropPreview.integrate(source: "nope", target: "c", in: Self.log) == nil)
        #expect(BranchDropPreview.integrate(source: "z", target: "c", in: Self.log) == nil)
        #expect(BranchDropPreview.move(from: "c", to: "z", in: Self.log) == nil)
    }

    @Test("Captions say what each choice does")
    func captions() {
        #expect(BranchDropPreview.mergeCaption(sourceOnly: 3, targetOnly: 2, source: "feature", target: "main")
                == "A merge commit brings 3 commits into main")
        #expect(BranchDropPreview.mergeCaption(sourceOnly: 1, targetOnly: 0, source: "feature", target: "main")
                == "Fast-forwards main by 1 commit")
        #expect(BranchDropPreview.mergeCaption(sourceOnly: 0, targetOnly: 4, source: "feature", target: "main")
                == "main already has feature")
        #expect(BranchDropPreview.rebaseCaption(sourceOnly: 3, targetOnly: 2, source: "feature", target: "main")
                == "Replays 3 commits after main's 2 commits")
        #expect(BranchDropPreview.rebaseCaption(sourceOnly: 3, targetOnly: 0, source: "feature", target: "main")
                == "feature is already on top of main")
        #expect(BranchDropPreview.moveCaption(dropped: 2, gained: 0, branch: "feature") == "feature moves back 2 commits")
        #expect(BranchDropPreview.moveCaption(dropped: 0, gained: 1, branch: "feature") == "feature moves forward 1 commit")
        #expect(BranchDropPreview.moveCaption(dropped: 1, gained: 2, branch: "feature")
                == "feature leaves 1 commit and takes 2 commits from another line")
    }
}
