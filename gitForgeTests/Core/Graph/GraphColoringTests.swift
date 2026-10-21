import Foundation
import Testing
@testable import gitForge

@Suite("GraphColoring")
struct GraphColoringTests {

    /// Stages 1 to 3 of the layout, chained as the engine chains them, then the colours.
    private func coloring(_ input: GraphInput) -> GraphColoring {
        let rowOf = input.rowIndex()
        var lines = GraphLines.build(input, rowOf: rowOf)
        let connections = GraphConnections.build(input, rowOf: rowOf, lines: &lines)
        let columns = GraphColumns.assign(input, lines: lines, connections: connections)
        return GraphColoring.assign(input, lines: lines, columns: columns)
    }

    @Test("Gitflow on a feature: fixed roles and the reference pool order")
    func gitflow() {
        let c = coloring(GraphInput(commits: GraphFixture.gitflow, headSha: "cartPayment",
                                    refs: GraphFixture.gitflowRefs(head: "feature/cart"), paletteSize: 4))
        #expect(c.role(.branch("feature/cart")) == .head)
        #expect(c.role(.branch("main")) == .main)
        #expect(c.role(.branch("develop")) == .develop)
        #expect(c.role(.branch("feature/search")) == .pool(0))
        #expect(c.role(.branch("release/1.1")) == .pool(1))
        #expect(c.role(.branch("hotfix/crash")) == .pool(2))
        #expect(c.role(.branch("feature/login")) == .pool(3))
    }

    @Test("With three colours, neighbours still differ")
    func threeColours() {
        let c = coloring(GraphInput(commits: GraphFixture.gitflow, headSha: "cartPayment",
                                    refs: GraphFixture.gitflowRefs(head: "feature/cart"), paletteSize: 3))
        #expect(c.role(.branch("feature/login")) == .pool(0))
        #expect(c.role(.branch("feature/login")) != c.role(.branch("hotfix/crash")))
    }

    @Test("A remote takes its local branch's role; detached HEAD and stashes have fixed roles")
    func fixedRoles() {
        let diverged = coloring(GraphInput(commits: GraphFixture.commits("r1 b\nl b\nb base\nbase"), headSha: "l",
            refs: [GraphFixture.local("feature", "l", head: true, upstream: "origin/feature", ahead: 1, behind: 1),
                   GraphFixture.remote("origin/feature", "r1")]))
        #expect(diverged.role(.remote("origin/feature")) == .head)
        let detached = coloring(GraphInput(commits: GraphFixture.commits("a b\nb"), headSha: "a"))
        #expect(detached.role(.head) == .head)
        let stash = coloring(GraphInput(commits: GraphFixture.commits("s b\nb"), stashShas: ["s"]))
        #expect(stash.role(.stash("s")) == .stash)
    }

    @Test("master and dev are trunks too", arguments: [("master", GraphColorRole.main), ("dev", .develop)])
    func trunkAliases(name: String, role: GraphColorRole) {
        let c = coloring(GraphInput(commits: GraphFixture.commits("f t\nt"), headSha: "f",
                                    refs: [GraphFixture.local("feature", "f", head: true), GraphFixture.local(name, "t")]))
        #expect(c.role(.branch(name)) == role)
    }

    // MARK: - Beyond the plan's cases

    @Test("HEAD on a trunk is .head, not the trunk's own role")
    func headOnTrunk() {
        let c = coloring(GraphInput(commits: GraphFixture.commits("m b\nb"), headSha: "m",
                                    refs: [GraphFixture.local("main", "m", head: true)]))
        #expect(c.role(.branch("main")) == .head)
    }

    @Test("A remote that no local branch continues takes a pool colour of its own")
    func remoteWithoutLocal() {
        let c = coloring(GraphInput(commits: GraphFixture.commits("f b\nr b\nb"), headSha: "f",
                                    refs: [GraphFixture.local("feature", "f", head: true),
                                           GraphFixture.remote("origin/other", "r")]))
        #expect(c.role(.remote("origin/other")) == .pool(0))
    }

    @Test("A remote takes the pool colour of its local branch, and a line beside the remote avoids it")
    func remoteSharesPoolColour() {
        // Columns: w 0, origin/w 1, z 2 and s 2 (z ends before s starts). w takes pool(0) and the remote copies
        // it at once; z takes pool(1), so usage ties again when s decides. s touches only the remote's line, so
        // only the copied colour can keep it off pool(0).
        let c = coloring(GraphInput(commits: GraphFixture.commits("""
            w1 b
            r1 b
            z1
            s1 s2
            s2
            b
            """), refs: [GraphFixture.local("feature/w", "w1", upstream: "origin/w", ahead: 1, behind: 1),
                         GraphFixture.remote("origin/w", "r1"),
                         GraphFixture.local("feature/z", "z1"), GraphFixture.local("feature/s", "s1")],
            paletteSize: 2))
        #expect(c.role(.branch("feature/w")) == .pool(0))
        #expect(c.role(.remote("origin/w")) == .pool(0))
        #expect(c.role(.branch("feature/z")) == .pool(1))
        #expect(c.role(.branch("feature/s")) == .pool(1))
    }

    @Test("Two locals on one upstream: the remote follows the same one whatever the ref order",
          arguments: [("feature/a", "feature/b", "feature/a"), ("feature/b", "main", "main")])
    func sharedUpstream(first: String, second: String, followed: String) {
        // The remote follows the lowest priority rank, then the name; the order of the refs does not matter.
        let locals = [GraphFixture.local(first, "l1", upstream: "origin/x", ahead: 1, behind: 1),
                      GraphFixture.local(second, "l2", upstream: "origin/x", ahead: 1, behind: 1)]
        let remote = GraphFixture.remote("origin/x", "r1")
        let commits = GraphFixture.commits("r1 base\nl1 base\nl2 base\nbase")
        let forward = coloring(GraphInput(commits: commits, refs: locals + [remote]))
        let backward = coloring(GraphInput(commits: commits, refs: [remote] + locals.reversed()))
        #expect(forward.roleOfOwner == backward.roleOfOwner)
        #expect(forward.role(.remote("origin/x")) == forward.role(.branch(followed)))
        #expect(forward.role(.branch(first)) != forward.role(.branch(second)))
    }

    @Test("A line avoids the colour of the line beside it, even when usage would pick that colour")
    func neighbourExclusion() {
        // a is long in column 0 and takes pool(0). b, beside it, takes pool(1), so usage ties at [1, 1].
        // c is beside a too (column 1, shared with b, which ended two rows above it): usage says pool(0),
        // the neighbour forbids it, and b, in c's own column, counts for nothing.
        let c = coloring(GraphInput(commits: GraphFixture.commits("""
            a1 a2
            b1 b2
            b2
            a2 a3
            c1 c2
            c2
            a3
            """), refs: [GraphFixture.local("feature/a", "a1"), GraphFixture.local("feature/b", "b1"),
                         GraphFixture.local("feature/c", "c1")],
            paletteSize: 2))
        #expect(c.role(.branch("feature/a")) == .pool(0))
        #expect(c.role(.branch("feature/b")) == .pool(1))
        #expect(c.role(.branch("feature/c")) == .pool(1))
    }

    @Test("A neighbour counts from two rows above or below a line, and not from three",
          arguments: [(fillers: 0, expected: GraphColorRole.pool(1)), (fillers: 1, expected: .pool(0))])
    func neighbourMargin(fillers: Int, expected: GraphColorRole) {
        // Palette of 3. Column 0 holds a (rows 0-2, pool 0) and then b (pool 2); e (pool 1) sits in column 1
        // beside a, and c (column 1, beside b) starts at row 4 or 5. b is always a neighbour of c. a ends at
        // row 2, which is within two rows of c's top only when c starts at row 4. Usage is [1, 1, 1], so c
        // takes pool(1) when it must skip pool(0) and pool(2), and pool(0) when it skips only pool(2).
        let chain = (0..<fillers).map { "bf\($0)" } + ["bEnd"]
        var rows = ["a1 a2", "e1", "a2", "b1 \(chain[0])"]
        for index in 0..<fillers { rows.append("\(chain[index]) \(chain[index + 1])") }
        rows += ["c1 c2", "bEnd", "c2"]
        let c = coloring(GraphInput(commits: GraphFixture.commits(rows.joined(separator: "\n")),
            refs: [GraphFixture.local("feature/a", "a1"), GraphFixture.local("feature/e", "e1"),
                   GraphFixture.local("feature/b", "b1"), GraphFixture.local("feature/c", "c1")],
            paletteSize: 3))
        #expect(c.role(.branch("feature/a")) == .pool(0))
        #expect(c.role(.branch("feature/e")) == .pool(1))
        #expect(c.role(.branch("feature/b")) == .pool(2))
        #expect(c.role(.branch("feature/c")) == expected)
    }

    @Test("When every colour is taken beside a line, the least used of all wins")
    func allColoursTaken() {
        // Column 0 holds x, p and q one after the other (pool 0, 1 and 0, so usage is [2, 1]). l, in column 1,
        // has p and q within two rows, so both colours are taken and it falls back to the least used: pool(1).
        let c = coloring(GraphInput(commits: GraphFixture.commits("""
            x1
            p1 p2
            p2
            q1 q2
            l1 l2
            q2
            l2
            """), refs: [GraphFixture.local("feature/x", "x1"), GraphFixture.local("feature/p", "p1"),
                         GraphFixture.local("feature/q", "q1"), GraphFixture.local("feature/l", "l1")],
            paletteSize: 2))
        #expect(c.role(.branch("feature/x")) == .pool(0))
        #expect(c.role(.branch("feature/p")) == .pool(1))
        #expect(c.role(.branch("feature/q")) == .pool(0))
        #expect(c.role(.branch("feature/l")) == .pool(1))
    }

    @Test("A local branch whose tip is not loaded gives its remote no role to take")
    func remoteOfUnloadedLocal() {
        let c = coloring(GraphInput(commits: GraphFixture.commits("f b\nr b\nb"), headSha: "f",
            refs: [GraphFixture.local("feature", "f", head: true),
                   GraphFixture.local("work", "gone", upstream: "origin/work", ahead: 1, behind: 1),
                   GraphFixture.remote("origin/work", "r")]))
        #expect(c.role(.remote("origin/work")) == .pool(0))
    }

    @Test("A stretch of HEAD's line runs down to the first commit of the next colour owner")
    func headStretchExtent() {
        // HEAD is feature/h at t, with feature/a on the same commit, so a owns t for colour and main owns p
        // and q. The step from t down to p (rows 0 to 2) takes a's colour, so a's stretch is rows 0-2 in
        // column 0. z takes pool(1) beside it. c starts at row 3 in column 1: its two-row margin reaches row
        // 1, so it sees a's stretch only because that stretch runs to row 2, not just to t's own row.
        let c = coloring(GraphInput(commits: GraphFixture.commits("""
            t p
            z1
            p q
            c1 c2
            q
            c2
            """), headSha: "t",
            refs: [GraphFixture.local("feature/h", "t", head: true), GraphFixture.local("feature/a", "t"),
                   GraphFixture.local("main", "p"), GraphFixture.local("feature/z", "z1"),
                   GraphFixture.local("feature/c", "c1")],
            paletteSize: 2))
        #expect(c.role(.branch("feature/h")) == .head)
        #expect(c.role(.branch("main")) == .main)
        #expect(c.role(.branch("feature/a")) == .pool(0))
        #expect(c.role(.branch("feature/z")) == .pool(1))
        #expect(c.role(.branch("feature/c")) == .pool(1))
    }

    @Test("A line that only shares HEAD's colour owner still gets one pool colour")
    func ownerWithoutOwnLine() {
        // feature/a and HEAD's feature/b both sit on `t`, and a sorts first: a owns the whole HEAD line.
        let c = coloring(GraphInput(commits: GraphFixture.commits("t b\nb"), headSha: "t",
                                    refs: [GraphFixture.local("feature/b", "t", head: true), GraphFixture.local("feature/a", "t")]))
        #expect(c.role(.branch("feature/b")) == .head)
        #expect(c.role(.branch("feature/a")) == .pool(0))
    }

    @Test("An empty palette leaves pool owners neutral")
    func emptyPalette() {
        let c = coloring(GraphInput(commits: GraphFixture.commits("f b\ns b\nb"), headSha: "f",
                                    refs: [GraphFixture.local("feature", "f", head: true), GraphFixture.local("side", "s")],
                                    paletteSize: 0))
        #expect(c.role(.branch("feature")) == .head)
        #expect(c.role(.branch("side")) == .neutral)
    }

    @Test("An owner the graph never saw is neutral")
    func missingOwner() {
        let c = coloring(GraphInput(commits: GraphFixture.commits("a b\nb"), headSha: "a"))
        #expect(c.role(.branch("nowhere")) == .neutral)
    }

    @Test("The order refs arrive in does not change the gitflow roles")
    func gitflowIndependentOfRefOrder() {
        let refs = GraphFixture.gitflowRefs(head: "feature/cart")
        let forward = coloring(GraphInput(commits: GraphFixture.gitflow, headSha: "cartPayment", refs: refs, paletteSize: 4))
        let backward = coloring(GraphInput(commits: GraphFixture.gitflow, headSha: "cartPayment", refs: refs.reversed(), paletteSize: 4))
        #expect(forward.roleOfOwner == backward.roleOfOwner)
        #expect(forward.roleOfOwner.count == 7)
    }

    @Test("A stretch on the first page keeps its colour when the next page loads")
    func nextPageNeighbours() {
        // Columns: main 0; x, y and a 1 in turn; origin/x 2 on page 2 only. x takes pool(0) and its remote copies
        // it at once; y takes pool(1), so usage ties when a decides. a runs past the end of page 1 and forks on
        // page 2, two rows below origin/x: unclipped, its window would reach the copied pool(0) and a would
        // change to pool(1) when page 2 loads. Page 1 alone gives pool(0), so that is what it must keep (§3.9).
        let commits = GraphFixture.commits("""
            m0 m1
            x1 m1
            m1 m2
            y1 m2
            m2 m3
            m3 m4
            a1 a2
            a2 m6
            m4 m5
            ox m5
            m5 m6
            m6
            """)
        let refs = [GraphFixture.local("main", "m0", head: true),
                    GraphFixture.local("feature/x", "x1", upstream: "origin/feature/x", ahead: 5, behind: 1),
                    GraphFixture.remote("origin/feature/x", "ox"),
                    GraphFixture.local("feature/y", "y1"), GraphFixture.local("feature/a", "a1")]
        let firstPage = coloring(GraphInput(commits: Array(commits.prefix(8)), pageEnds: [8], headSha: "m0",
                                            refs: refs, paletteSize: 2))
        let bothPages = coloring(GraphInput(commits: commits, pageEnds: [8, 12], headSha: "m0", refs: refs,
                                            paletteSize: 2))
        #expect(firstPage.role(.branch("feature/a")) == .pool(0))
        #expect(bothPages.role(.branch("feature/x")) == .pool(0))
        #expect(bothPages.role(.remote("origin/feature/x")) == .pool(0))
        #expect(bothPages.role(.branch("feature/y")) == .pool(1))
        #expect(bothPages.role(.branch("feature/a")) == .pool(0))
    }
}
