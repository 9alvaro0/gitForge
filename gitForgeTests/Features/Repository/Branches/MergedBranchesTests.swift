import Foundation
import Testing
@testable import gitForge

@Suite("MergedBranches and GitRef.fullRefName")
struct MergedBranchesTests {

    private static func local(_ name: String) -> GitRef {
        GitRef(name: name, kind: .localBranch, targetSha: "x", isHead: false)
    }

    @Test("Branches outside --no-merged are merged; the current one never is")
    func names() {
        let branches = ["main", "feature/a", "feature/b", "old"].map(Self.local)
        let merged = MergedBranches.names(localBranches: branches,
                                          unmergedRefs: ["refs/heads/feature/a"],
                                          currentBranch: "main")
        #expect(merged == ["feature/b", "old"])
    }

    @Test("Detached HEAD: every branch HEAD contains counts")
    func detached() {
        let merged = MergedBranches.names(localBranches: [Self.local("main")],
                                          unmergedRefs: [], currentBranch: nil)
        #expect(merged == ["main"])
    }

    @Test("fullRefName qualifies each kind")
    func fullRefName() {
        #expect(Self.local("feature/x").fullRefName == "refs/heads/feature/x")
        #expect(GitRef(name: "origin/main", kind: .remoteBranch(remote: "origin"), targetSha: "x", isHead: false)
            .fullRefName == "refs/remotes/origin/main")
        #expect(GitRef(name: "v1", kind: .tag, targetSha: "x", isHead: false).fullRefName == "refs/tags/v1")
    }
}
