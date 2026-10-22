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

    @Test("A detached HEAD seeds local reach without any branch")
    func detachedHead() {
        let input = GraphInput(commits: GraphFixture.commits("u2 u1\nu1 l\nl base\nbase"), headSha: "u1",
                               refs: [GraphFixture.remote("origin/main", "u2")])
        #expect(GraphReachability.ghostRows(input, rowOf: input.rowIndex()) == [true, false, false, false])
    }

    @Test("A stash keeps the commit it was taken on local, even below a remote tip")
    func stashSeedsLocal() {
        let input = GraphInput(commits: GraphFixture.commits("u2 s\ns l\nl base\nbase"), headSha: "base",
                               refs: [GraphFixture.remote("origin/main", "u2")], stashShas: ["s"])
        #expect(GraphReachability.ghostRows(input, rowOf: input.rowIndex()) == [true, false, false, false])
    }

    @Test("Local reach flows to a merge's second parent")
    func secondParent() {
        let input = GraphInput(commits: GraphFixture.commits("m a b\na base\nb base\nbase"), headSha: "m",
                               refs: [GraphFixture.local("main", "m", head: true), GraphFixture.remote("origin/b", "b")])
        #expect(GraphReachability.ghostRows(input, rowOf: input.rowIndex()) == [false, false, false, false])
    }

    @Test("A remote whose tip is not loaded marks nothing")
    func unloadedRemoteTip() {
        let input = GraphInput(commits: GraphFixture.commits("l base\nbase"), headSha: "l",
                               refs: [GraphFixture.local("main", "l", head: true), GraphFixture.remote("origin/main", "gone")])
        #expect(GraphReachability.ghostRows(input, rowOf: input.rowIndex()) == [false, false])
    }
}
