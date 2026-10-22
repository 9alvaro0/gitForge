import Foundation
import Testing
@testable import gitForge

@Suite("CommitGraphEngine")
struct CommitGraphEngineTests {

    /// Rows: 0 `o`, 1 `r2`, 2 `f`, 3 `r1`, 4 `base`. HEAD's `feature` sits on `f`, and `origin/main`
    /// stands in for the missing local main with its tip two commits ahead on `r2`.
    private static let remoteTrunk = GraphInput(
        commits: GraphFixture.commits("o base\nr2 r1\nf r1\nr1 base\nbase"), headSha: "f",
        refs: [GraphFixture.local("feature", "f", head: true), GraphFixture.local("other", "o"),
               GraphFixture.remote("origin/main", "r2")],
        remoteTrunks: ["origin/main": 0])

    private static func gitflow(head: String = "feature/cart", pageEnds: [Int] = [], count: Int = 24) -> GraphInput {
        let commits = Array(GraphFixture.gitflow.prefix(count))
        let headSha = GraphFixture.gitflowRefs(head: head).first { $0.isHead }?.targetSha
        return GraphInput(commits: commits, pageEnds: pageEnds, headSha: headSha,
                          refs: GraphFixture.gitflowRefs(head: head), paletteSize: 4)
    }

    @Test("Empty input gives an empty layout")
    func empty() { #expect(CommitGraphEngine.layout(GraphInput(commits: [])) == .empty) }

    @Test("A linear history is straight steps in column 0")
    func linear() {
        let layout = CommitGraphEngine.layout(GraphInput(commits: GraphFixture.commits("c b\nb a\na"), headSha: "c",
                                                         refs: [GraphFixture.local("main", "c", head: true)]))
        let straight = GraphStep(from: 0, to: 0, color: .head, stroke: .solid)
        #expect(layout.rows.map(\.stepsBelow) == [[straight], [straight], []])
        #expect(layout.rows[0].stepsAbove.isEmpty)
        #expect(layout.columnCount == 1)
    }

    @Test("Gitflow on a feature: reference steps")
    func gitflowSteps() {
        let rows = CommitGraphEngine.layout(Self.gitflow()).rows
        #expect(rows[4].stepsBelow.contains(GraphStep(from: 2, to: 4, color: .pool(1), stroke: .solid)))
        #expect(rows[7].stepsBelow.contains(GraphStep(from: 0, to: 3, color: .develop, stroke: .solid)))
        #expect(rows[13].stepsBelow.contains(GraphStep(from: 3, to: 2, color: .develop, stroke: .solid)))
        #expect(rows[13].stepsBelow.contains(GraphStep(from: 2, to: 5, color: .pool(2), stroke: .solid)))
        #expect(rows[18].stepsBelow.contains(GraphStep(from: 2, to: 0, color: .develop, stroke: .solid)))
        #expect(rows[9].stepsBelow.contains(GraphStep(from: 0, to: 0, color: .head, stroke: .solid)))
        #expect(rows[19].stepsBelow.contains(GraphStep(from: 0, to: 0, color: .develop, stroke: .solid)))
        #expect(rows[22].stepsBelow == [GraphStep(from: 0, to: 0, color: .main, stroke: .solid)])
        #expect(rows[19].node == GraphNode(column: 0, kind: .commit, color: .develop, isGhost: false))
        #expect(rows[7].node.kind == .merge)
    }

    @Test("Every HEAD keeps the invariants", arguments: ["main", "develop", "release/1.1", "hotfix/crash",
                                                         "feature/login", "feature/cart", "feature/search"])
    func invariants(head: String) {
        let input = Self.gitflow(head: head)
        let layout = CommitGraphEngine.layout(input)
        GraphInvariants.check(layout, input)
        let headRow = GraphFixture.row(input.headSha!, in: input.commits)
        #expect(layout.rows[headRow].node.column == 0)
    }

    @Test("Loading the next page doesn't move what was drawn")
    func stability() {
        let first = CommitGraphEngine.layout(Self.gitflow(pageEnds: [12], count: 12)).rows
        let full = CommitGraphEngine.layout(Self.gitflow(pageEnds: [12, 24])).rows
        #expect(Array(full.prefix(11)) == Array(first.prefix(11)))
        #expect(full[11].node == first[11].node)
        #expect(full[11].stepsAbove == first[11].stepsAbove)
    }

    @Test("Ghost commits and their steps")
    func ghosts() {
        let rows = CommitGraphEngine.layout(GraphInput(commits: GraphFixture.commits("u2 u1\nu1 l\nl base\nbase"), headSha: "l",
            refs: [GraphFixture.local("main", "l", head: true, upstream: "origin/main", ahead: 0, behind: 2),
                   GraphFixture.remote("origin/main", "u2")])).rows
        #expect(rows.map(\.node.isGhost) == [true, true, false, false])
        #expect(rows[1].stepsBelow == [GraphStep(from: 0, to: 0, color: .head, stroke: .ghost)])
        #expect(rows[2].stepsBelow == [GraphStep(from: 0, to: 0, color: .head, stroke: .solid)])
    }

    @Test("A stash is a dashed side step into its commit")
    func stash() {
        let rows = CommitGraphEngine.layout(GraphInput(commits: GraphFixture.commits("s a\na b\nb"), headSha: "a",
            refs: [GraphFixture.local("main", "a", head: true)], stashShas: ["s"])).rows
        #expect(rows[0].node == GraphNode(column: 1, kind: .stash, color: .stash, isGhost: false))
        #expect(rows[0].stepsBelow == [GraphStep(from: 1, to: 0, color: .stash, stroke: .stash)])
    }

    @Test("A merge whose parent isn't loaded runs a neutral track to the bottom")
    func openTrack() {
        let rows = CommitGraphEngine.layout(GraphInput(commits: GraphFixture.commits("m a x\na"), headSha: "m",
            refs: [GraphFixture.local("main", "m", head: true)])).rows
        #expect(rows[0].stepsBelow.contains(GraphStep(from: 0, to: 1, color: .neutral, stroke: .solid)))
        #expect(rows[1].stepsBelow.contains(GraphStep(from: 1, to: 1, color: .neutral, stroke: .solid)))
    }

    @Test("Detached HEAD mid-history and orphan roots keep the invariants")
    func edgeShapes() {
        let detached = GraphInput(commits: GraphFixture.gitflow, headSha: "devBase", refs: GraphFixture.gitflowRefs(head: nil))
        let detachedLayout = CommitGraphEngine.layout(detached)
        GraphInvariants.check(detachedLayout, detached)
        #expect(detachedLayout.rows[19].node.column == 0)
        let orphans = GraphInput(commits: GraphFixture.commits("a r1\nb r2\nr1\nr2"), headSha: "a",
                                 refs: [GraphFixture.local("main", "a", head: true), GraphFixture.local("gh-pages", "b")])
        let orphanLayout = CommitGraphEngine.layout(orphans)
        GraphInvariants.check(orphanLayout, orphans)
        // A root has nothing below its own node (another line may still pass by in its row).
        for row in [orphanLayout.rows[2], orphanLayout.rows[3]] {
            #expect(!row.stepsBelow.contains { $0.from == row.node.column })
        }
    }

    // MARK: - Beyond the plan's reference cases

    @Test("Steps at each boundary are sorted by columns; widths and column count follow them")
    func orderAndWidth() {
        let layout = CommitGraphEngine.layout(Self.gitflow())
        for row in layout.rows {
            #expect(row.stepsBelow.map { [$0.from, $0.to] } == row.stepsBelow.map { [$0.from, $0.to] }
                .sorted { $0.lexicographicallyPrecedes($1) })
        }
        #expect(layout.rows[13].stepsBelow.map { [$0.from, $0.to] } == [[0, 0], [1, 1], [2, 2], [2, 5], [3, 2]])
        #expect(layout.rows[0].width == 4)
        #expect(layout.rows[13].width == 6)
        // Hotfix and main end in row 22 from the right: what arrives from above counts too.
        #expect(layout.rows[22].width == 6)
        #expect(layout.rows[23].width == 1)
        #expect(layout.columnCount == 6)
    }

    @Test("A merge only on the server joins a local line with ghost steps down to its tip")
    func ghostJoin() {
        let input = GraphInput(commits: GraphFixture.commits("m m0 f1\nm0 base\nf1 base\nbase"), headSha: "m0",
            refs: [GraphFixture.local("main", "m0", head: true, upstream: "origin/main", ahead: 0, behind: 1),
                   GraphFixture.remote("origin/main", "m"),
                   GraphFixture.local("feature/f", "f1")])
        let layout = CommitGraphEngine.layout(input)
        GraphInvariants.check(layout, input)
        let rows = layout.rows
        #expect(rows[0].stepsBelow == [GraphStep(from: 0, to: 0, color: .head, stroke: .ghost),
                                       GraphStep(from: 0, to: 1, color: .pool(0), stroke: .ghost)])
        #expect(rows[1].stepsBelow == [GraphStep(from: 0, to: 0, color: .head, stroke: .solid),
                                       GraphStep(from: 1, to: 1, color: .pool(0), stroke: .ghost)])
        #expect(rows[2].stepsBelow == [GraphStep(from: 0, to: 0, color: .head, stroke: .solid),
                                       GraphStep(from: 1, to: 0, color: .pool(0), stroke: .solid)])
    }

    @Test("An octopus merge connects each extra parent: a join, and a neutral track for the unloaded one")
    func octopus() {
        let input = GraphInput(commits: GraphFixture.commits("m a x y\na b\nx b\nb"), headSha: "m",
                               refs: [GraphFixture.local("main", "m", head: true)])
        let layout = CommitGraphEngine.layout(input)
        GraphInvariants.check(layout, input)
        let rows = layout.rows
        #expect(rows[0].node == GraphNode(column: 0, kind: .merge, color: .head, isGhost: false))
        #expect(rows[0].stepsBelow == [GraphStep(from: 0, to: 0, color: .head, stroke: .solid),
                                       GraphStep(from: 0, to: 1, color: .pool(0), stroke: .solid),
                                       GraphStep(from: 0, to: 2, color: .neutral, stroke: .solid)])
        #expect(rows[2].stepsBelow == [GraphStep(from: 0, to: 0, color: .head, stroke: .solid),
                                       GraphStep(from: 1, to: 0, color: .pool(0), stroke: .solid),
                                       GraphStep(from: 2, to: 2, color: .neutral, stroke: .solid)])
        #expect(rows[3].stepsBelow == [GraphStep(from: 2, to: 2, color: .neutral, stroke: .solid)])
        #expect(rows.map(\.width) == [3, 3, 3, 3])
    }

    @Test("A join into a line that already passes fuses with it below the merge")
    func fusedJoin() {
        // main merges develop at d2, then develop moves on to d3 above the merge.
        let input = GraphInput(commits: GraphFixture.commits("d3 d2\nM m1 d2\nm1 base\nd2 base\nbase"), headSha: "M",
                               refs: [GraphFixture.local("main", "M", head: true), GraphFixture.local("develop", "d3")])
        let layout = CommitGraphEngine.layout(input)
        GraphInvariants.check(layout, input)
        #expect(layout.rows[1].stepsBelow == [GraphStep(from: 0, to: 0, color: .head, stroke: .solid),
                                              GraphStep(from: 0, to: 1, color: .develop, stroke: .solid),
                                              GraphStep(from: 1, to: 1, color: .develop, stroke: .solid)])
    }

    @Test("The invariants accept a repeated landing only for joins fusing with a straight line",
          arguments: [
              // (steps on the boundary, landings that must be reported) with the node above
              // in column 0 and the node below in column 2.
              ([(1, 1), (0, 1)], 0),
              ([(1, 1), (0, 1), (0, 1)], 0),
              ([(1, 1), (3, 1)], 1),
              ([(0, 1), (0, 1)], 1),
              ([(1, 1), (0, 1), (3, 1)], 1),
          ])
    func fusedJoinExemption(steps: [(Int, Int)], reported: Int) {
        let node = { (column: Int) in GraphNode(column: column, kind: .commit, color: .neutral, isGhost: false) }
        let below = steps.map { GraphStep(from: $0.0, to: $0.1, color: .neutral, stroke: .solid) }
        let input = GraphInput(commits: GraphFixture.commits("a\nb"))
        let layout = GraphLayout(rows: [GraphRow(node: node(0), stepsAbove: [], stepsBelow: below, width: 4),
                                        GraphRow(node: node(2), stepsAbove: below, stepsBelow: [], width: 4)],
                                 columnCount: 4)
        #expect(GraphInvariants.violations(layout, input).filter { $0.contains("reach column") }.count == reported)
        // Below the last row nothing can join, so the same steps there are always reported.
        let bottom = GraphLayout(rows: [GraphRow(node: node(0), stepsAbove: [], stepsBelow: below, width: 4)],
                                 columnCount: 4)
        #expect(GraphInvariants.violations(bottom, GraphInput(commits: GraphFixture.commits("a")))
            .filter { $0.contains("reach column") }.count == 1)
    }

    @Test("A track to the first row of the next page enters it in one step")
    func trackIntoNextPage() {
        let commits = GraphFixture.commits("a m\nm b x\nx c\nb c\nc")
        let refs = [GraphFixture.local("main", "a", head: true)]
        let firstPage = GraphInput(commits: Array(commits.prefix(2)), pageEnds: [2], headSha: "a", refs: refs)
        let bothPages = GraphInput(commits: commits, pageEnds: [2, 5], headSha: "a", refs: refs)
        let first = CommitGraphEngine.layout(firstPage)
        let full = CommitGraphEngine.layout(bothPages)
        GraphInvariants.check(first, firstPage)
        GraphInvariants.check(full, bothPages)
        // Before the parent loads, the track runs to the bottom edge in its own column.
        #expect(first.rows[1].stepsBelow == [GraphStep(from: 0, to: 0, color: .head, stroke: .solid),
                                             GraphStep(from: 0, to: 1, color: .neutral, stroke: .solid)])
        // The parent is the very next row: the step from the merge goes straight into its node.
        #expect(full.rows[1].stepsBelow == [GraphStep(from: 0, to: 0, color: .head, stroke: .solid),
                                            GraphStep(from: 0, to: 2, color: .neutral, stroke: .solid)])
        #expect(full.rows[0] == first.rows[0])
        #expect(full.rows[1].node == first.rows[1].node)
        #expect(full.rows[1].stepsAbove == first.rows[1].stepsAbove)
    }

    @Test("Without a local main, origin/main is the trunk: its column, its colour, its server-only commits ghosts")
    func remoteTrunkLayout() {
        let layout = CommitGraphEngine.layout(Self.remoteTrunk)
        GraphInvariants.check(layout, Self.remoteTrunk)
        #expect(layout.rows[1].node == GraphNode(column: 1, kind: .commit, color: .main, isGhost: true))
        #expect(layout.rows[3].node == GraphNode(column: 0, kind: .commit, color: .main, isGhost: false))
        #expect(layout.rows[0].node.column == 2)
    }

    // Rows: 0 o, 1 u3, 2 f, 3 u2 | 4 u1, 5 l, 6 base.
    @Test("A branch behind its upstream by more than a page: page 1 stays as it was when its tip loads")
    func behindAcrossPages() {
        let commits = GraphFixture.commits("o base\nu3 u2\nf base\nu2 u1\nu1 l\nl base\nbase")
        let refs = [GraphFixture.local("feature", "f", head: true), GraphFixture.local("other", "o"),
                    GraphFixture.local("main", "l", upstream: "origin/main", ahead: 0, behind: 3),
                    GraphFixture.remote("origin/main", "u3")]
        let first = CommitGraphEngine.layout(GraphInput(commits: Array(commits.prefix(4)), pageEnds: [4],
                                                        headSha: "f", refs: refs)).rows
        let full = CommitGraphEngine.layout(GraphInput(commits: commits, pageEnds: [4, 7], headSha: "f", refs: refs)).rows
        #expect(Array(full.prefix(3)) == Array(first.prefix(3)))
        #expect(full[3].node == first[3].node && full[3].stepsAbove == first[3].stepsAbove)
        #expect(full[1].node == GraphNode(column: 1, kind: .commit, color: .main, isGhost: true))
    }

    // Rows: 0 r1 (origin/feature), 1 o (other) | 2 l (feature), 3 b, 4 base. Today the remote waits for
    // its local, so once page 2 loads `other` takes pool 0 first and the remote changes to pool 1.
    @Test("A remote whose local branch loads on the next page keeps its colour, and the branch shares it")
    func remoteColourAcrossPages() {
        let commits = GraphFixture.commits("r1 b\no base\nl b\nb base\nbase")
        let refs = [GraphFixture.local("main", "base", head: true), GraphFixture.local("other", "o"),
                    GraphFixture.local("feature", "l", upstream: "origin/feature", ahead: 1, behind: 1),
                    GraphFixture.remote("origin/feature", "r1")]
        let first = CommitGraphEngine.layout(GraphInput(commits: Array(commits.prefix(2)), pageEnds: [2],
                                                        headSha: "base", refs: refs)).rows
        let full = CommitGraphEngine.layout(GraphInput(commits: commits, pageEnds: [2, 5], headSha: "base", refs: refs)).rows
        #expect(full[0] == first[0])
        #expect(full[1].node == first[1].node && full[1].stepsAbove == first[1].stepsAbove)
        #expect(full[2].node.color == full[0].node.color)
    }

    @Test("Only ahead of its upstream: nothing is a ghost and the remote draws no line")
    func aheadOnly() {
        let layout = CommitGraphEngine.layout(GraphInput(commits: GraphFixture.commits("l2 l1\nl1 base\nbase"), headSha: "l2",
            refs: [GraphFixture.local("main", "l2", head: true, upstream: "origin/main", ahead: 1, behind: 0),
                   GraphFixture.remote("origin/main", "l1")]))
        #expect(layout.rows.allSatisfy { !$0.node.isGhost })
        #expect(layout.columnCount == 1)
    }

    @Test("A branch only on the server: a ghost line in a palette colour when loaded, nothing when not")
    func serverOnly() {
        let refs = [GraphFixture.local("main", "m", head: true), GraphFixture.remote("origin/release", "s1")]
        let loaded = CommitGraphEngine.layout(GraphInput(commits: GraphFixture.commits("s1 base\nm base\nbase"),
                                                         headSha: "m", refs: refs))
        #expect(loaded.rows[0].node.isGhost && loaded.rows[0].node.column == 1)
        #expect(loaded.rows[0].node.color == .pool(0))
        let unloaded = CommitGraphEngine.layout(GraphInput(commits: GraphFixture.commits("m base\nbase"), headSha: "m", refs: refs))
        #expect(unloaded.columnCount == 1)
    }
}
