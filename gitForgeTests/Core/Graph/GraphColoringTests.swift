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

    @Test("A remote takes the pool colour of its local branch, and the line beside it avoids that colour")
    func remoteSharesPoolColour() {
        // work (row 0) and origin/work (row 1) have diverged. Columns: main 0, work 1, origin/work 2, side 3,
        // so side touches the remote's line but not its local branch's.
        let c = coloring(GraphInput(commits: GraphFixture.commits("l b\nr1 b\ns b\nm b\nb"), headSha: "m",
            refs: [GraphFixture.local("main", "m", head: true),
                   GraphFixture.local("work", "l", upstream: "origin/work", ahead: 1, behind: 1),
                   GraphFixture.remote("origin/work", "r1"),
                   GraphFixture.local("side", "s")]))
        #expect(c.role(.branch("work")) == .pool(0))
        #expect(c.role(.remote("origin/work")) == .pool(0))
        #expect(c.role(.branch("side")) == .pool(1))
    }

    @Test("A local branch whose tip is not loaded gives its remote no role to take")
    func remoteOfUnloadedLocal() {
        let c = coloring(GraphInput(commits: GraphFixture.commits("f b\nr b\nb"), headSha: "f",
            refs: [GraphFixture.local("feature", "f", head: true),
                   GraphFixture.local("work", "gone", upstream: "origin/work", ahead: 1, behind: 1),
                   GraphFixture.remote("origin/work", "r")]))
        #expect(c.role(.remote("origin/work")) == .pool(0))
    }

    @Test("HEAD's line takes the colour of whoever owns each stretch, and neighbours avoid it")
    func headLineSplitByColourOwner() {
        // HEAD is feature/y (y1, x1, m). feature/x sits on x1 and main on m, so in the colour walk x owns x1
        // and main owns m. feature/z, in column 1, runs beside the stretch of x.
        let c = coloring(GraphInput(commits: GraphFixture.commits("y1 x1\nz1 m\nx1 m\nm"), headSha: "y1",
            refs: [GraphFixture.local("feature/y", "y1", head: true), GraphFixture.local("feature/x", "x1"),
                   GraphFixture.local("feature/z", "z1"), GraphFixture.local("main", "m")]))
        #expect(c.role(.branch("feature/y")) == .head)
        #expect(c.role(.branch("main")) == .main)
        #expect(c.role(.branch("feature/z")) == .pool(0))
        #expect(c.role(.branch("feature/x")) == .pool(1))
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

    @Test("The order refs arrive in does not change the roles")
    func independentOfRefOrder() {
        let refs = GraphFixture.gitflowRefs(head: "feature/cart")
        let forward = coloring(GraphInput(commits: GraphFixture.gitflow, headSha: "cartPayment", refs: refs, paletteSize: 4))
        let backward = coloring(GraphInput(commits: GraphFixture.gitflow, headSha: "cartPayment", refs: refs.reversed(), paletteSize: 4))
        #expect(forward.roleOfOwner == backward.roleOfOwner)
        #expect(forward.roleOfOwner.count == 7)
    }
}
