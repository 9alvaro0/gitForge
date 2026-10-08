import Foundation
import Testing
@testable import gitForge

/// The graph layout engine had no tests at all (audit A09). These pin its
/// invariants rather than exact columns, so legitimate tuning of the packing
/// doesn't break them while real regressions do.
@Suite("GraphLayoutEngine")
struct GraphLayoutEngineTests {

    private static func commit(_ sha: String, _ parents: [String] = []) -> Commit {
        Commit(sha: sha, parentShas: parents, authorName: "T", authorEmail: "t@t",
               authorDate: Date(timeIntervalSince1970: 0), subject: sha)
    }

    private static func ref(_ name: String, at sha: String) -> [String: [GitRef]] {
        [sha: [GitRef(name: name, kind: .localBranch, targetSha: sha, isHead: false)]]
    }

    /// Invariants every layout must satisfy.
    private static func checkInvariants(_ commits: [Commit], _ result: (rows: [GraphRowLayout], maxLanes: Int)) {
        #expect(result.rows.count == commits.count)
        for row in result.rows {
            #expect(row.commitLane >= 0 && row.commitLane < row.totalLanes)
            #expect(row.totalLanes <= result.maxLanes)
            for occupation in row.lanesAtTop + row.lanesAtBottom + row.mergesIn + row.mergesOut {
                #expect(occupation.lane < result.maxLanes)
            }
        }
    }

    @Test("Empty log yields no rows and a single lane")
    func empty() {
        let result = GraphLayoutEngine.layouts(for: [])
        #expect(result.rows.isEmpty)
        #expect(result.maxLanes == 1)
    }

    @Test("Linear history stays in one lane")
    func linear() {
        let commits = [Self.commit("d", ["c"]), Self.commit("c", ["b"]), Self.commit("b", ["a"]), Self.commit("a")]
        let result = GraphLayoutEngine.layouts(for: commits)
        Self.checkInvariants(commits, result)
        #expect(result.maxLanes == 1)
        #expect(result.rows.allSatisfy { $0.commitLane == 0 && !$0.isMerge })
    }

    @Test("A merged feature branch opens a second lane and the first-parent chain keeps its lane")
    func branchAndMerge() {
        // m merges feature f into main a; both fork from b.
        let commits = [
            Self.commit("m", ["a", "f"]),
            Self.commit("f", ["b"]),
            Self.commit("a", ["b"]),
            Self.commit("b", ["r"]),
            Self.commit("r"),
        ]
        let result = GraphLayoutEngine.layouts(for: commits)
        Self.checkInvariants(commits, result)
        let rows = Dictionary(uniqueKeysWithValues: zip(commits.map(\.sha), result.rows))

        #expect(result.maxLanes == 2)
        #expect(rows["m"]!.isMerge)
        #expect(!rows["m"]!.mergesOut.isEmpty)
        // First-parent chain m → a → b stays in one lane; f sits elsewhere.
        #expect(rows["m"]!.commitLane == rows["a"]!.commitLane)
        #expect(rows["a"]!.commitLane == rows["b"]!.commitLane)
        #expect(rows["f"]!.commitLane != rows["a"]!.commitLane)
        // Once the branches converge nothing else stays open.
        #expect(rows["r"]!.lanesAtBottom.isEmpty)
    }

    @Test("Columns follow topo order (no trunk pinning), but main keeps its priority styling")
    func mainNotPinnedButStyled() {
        // By design (see Pass 2 in the engine): pinning trunks to column 0 was
        // tried and produced worse layouts when main's tip sat low in the log.
        // The first-opened lane takes the leftmost column; `main` is still
        // recognised so the renderer paints it with the fixed trunk colour.
        let commits = [Self.commit("f", ["b"]), Self.commit("m", ["b"]), Self.commit("b")]
        let refs = Self.ref("feature/x", at: "f").merging(Self.ref("main", at: "m")) { $0 + $1 }
        let result = GraphLayoutEngine.layouts(for: commits, refsBySha: refs)
        Self.checkInvariants(commits, result)
        #expect(result.rows[0].commitLane == 0)
        #expect(result.rows[1].commitLane == 1)
        #expect(result.rows[1].commitPriorityRank == 0)
        #expect(result.rows[0].commitPriorityRank == nil)
    }

    @Test("A stash commit's lane is marked as a stash lane")
    func stashLane() {
        let commits = [Self.commit("s", ["b", "i"]), Self.commit("b")]
        let result = GraphLayoutEngine.layouts(for: commits, stashShas: ["s"])
        #expect(result.rows[0].commitIsStash)
        #expect(!result.rows[1].commitIsStash)
    }

    @Test("Gitflow priority ranks", arguments: [
        ("main", 0), ("master", 0), ("develop", 1), ("dev", 1),
        ("release/1.2", 2), ("trunk", 3),
    ])
    func priorityRanks(name: String, rank: Int) {
        #expect(GraphLayoutEngine.priorityRank(forName: name) == rank)
    }

    @Test("Ordinary branches have no priority rank")
    func noPriority() {
        #expect(GraphLayoutEngine.priorityRank(forName: "feature/login") == nil)
        #expect(GraphLayoutEngine.priorityRank(forName: "mainline") == nil)
    }
}
