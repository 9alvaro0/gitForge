import Foundation
import Testing
@testable import gitForge

@Suite("Graph v2 — node style and HEAD lane")
struct GraphNodeStyleTests {

    private static func row(merge: Bool = false, stash: Bool = false, branchId: Int = 0) -> GraphRowLayout {
        GraphRowLayout(commitLane: 0, commitBranchId: branchId, lanesAtTop: [], lanesAtBottom: [],
                       mergesIn: [], mergesOut: [], totalLanes: 1, isMerge: merge, commitIsStash: stash)
    }

    @Test("Stash wins, then HEAD, then merge, else a plain commit")
    func precedence() {
        #expect(GraphNodeStyle.for(Self.row(), isHeadCommit: false) == .commit)
        #expect(GraphNodeStyle.for(Self.row(merge: true), isHeadCommit: false) == .merge)
        #expect(GraphNodeStyle.for(Self.row(merge: true), isHeadCommit: true) == .head)
        #expect(GraphNodeStyle.for(Self.row(stash: true), isHeadCommit: true) == .stash)
    }

    @Test("The HEAD lane is the branch id of the row holding the HEAD commit")
    func headBranch() {
        let commits = ["a", "b", "c"].map {
            Commit(sha: $0, parentShas: [], authorName: "T", authorEmail: "t@example.com",
                   authorDate: .init(timeIntervalSince1970: 0), subject: $0)
        }
        let layouts = [Self.row(branchId: 4), Self.row(branchId: 7), Self.row(branchId: 9)]
        #expect(GraphHead.branchId(headSha: "b", commits: commits, layouts: layouts) == 7)
        #expect(GraphHead.branchId(headSha: "zzz", commits: commits, layouts: layouts) == nil)
        #expect(GraphHead.branchId(headSha: nil, commits: commits, layouts: layouts) == nil)
        #expect(GraphHead.branchId(headSha: "c", commits: commits, layouts: Array(layouts.prefix(2))) == nil)
    }
}
