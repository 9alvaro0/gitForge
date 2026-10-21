import Foundation
import Testing
@testable import gitForge

@Suite("GraphReachability")
struct GraphReachabilityTests {
    private static let behind = GraphFixture.commits("u2 u1\nu1 l\nl base\nbase")

    @Test("Commits only on the remote are ghosts")
    func remoteOnly() {
        let input = GraphInput(commits: Self.behind, headSha: "l",
                               refs: [GraphFixture.local("main", "l", head: true, upstream: "origin/main", ahead: 0, behind: 2),
                                      GraphFixture.remote("origin/main", "u2")])
        #expect(GraphReachability.ghostRows(input, rowOf: input.rowIndex()) == [true, true, false, false])
    }

    @Test("A tag fetched onto a remote commit doesn't make it local")
    func tagsDontCount() {
        let input = GraphInput(commits: Self.behind, headSha: "l",
                               refs: [GraphFixture.local("main", "l", head: true), GraphFixture.remote("origin/main", "u2"),
                                      GraphFixture.tag("v2", "u2")])
        #expect(GraphReachability.ghostRows(input, rowOf: input.rowIndex())[0])
    }

    @Test("Without remote refs nothing is a ghost; stashes are local")
    func noRemotes() {
        let input = GraphInput(commits: GraphFixture.commits("s base\nbase"), stashShas: ["s"])
        #expect(GraphReachability.ghostRows(input, rowOf: input.rowIndex()) == [false, false])
    }

    @Test("Remote commits also reachable from a local branch are not ghosts")
    func shared() {
        let input = GraphInput(commits: Self.behind, headSha: "u2",
                               refs: [GraphFixture.local("main", "u2", head: true), GraphFixture.remote("origin/main", "u1")])
        #expect(GraphReachability.ghostRows(input, rowOf: input.rowIndex()) == [false, false, false, false])
    }
}
