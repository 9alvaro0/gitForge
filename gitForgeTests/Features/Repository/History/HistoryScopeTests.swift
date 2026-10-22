import Foundation
import Testing
@testable import gitForge

@Suite("HistoryScope")
struct HistoryScopeTests {

    private func scope(_ refs: [GitRef], unmerged: [String] = [], stashes: [Stash] = [],
                       trunks: [String: Int] = [:], all: Bool = false) -> HistoryScope {
        HistoryScope.make(refs: refs, unmergedLocalBranchRefs: unmerged, stashes: stashes,
                          remoteTrunks: trunks, includesAllRemotes: all)
    }

    @Test("Without remotes in scope it is what it was: HEAD, unmerged branches, --tags, stashes")
    func plain() {
        let s = scope([GraphFixture.local("main", "m", head: true, upstream: "origin/main", ahead: 0, behind: 0),
                       GraphFixture.remote("origin/main", "m")],
                      unmerged: ["refs/heads/feature"], stashes: [Stash(index: 0, sha: "s1", subject: "WIP")])
        #expect(s.revisions == ["HEAD", "refs/heads/feature", "--tags", "s1"])
        #expect(s.remoteTips.isEmpty && s.stashShas == ["s1"])
    }

    @Test("A branch behind its upstream loads the upstream's tip; ahead-only and gone upstreams don't")
    func behindUpstreams() {
        var gone = GraphFixture.local("fix", "x", upstream: "origin/fix", ahead: 0, behind: 0)
        gone.upstreamGone = true
        let s = scope([GraphFixture.local("main", "m", upstream: "origin/main", ahead: 0, behind: 2),
                       GraphFixture.remote("origin/main", "u2"),
                       GraphFixture.local("feature", "f", upstream: "origin/feature", ahead: 1, behind: 0),
                       GraphFixture.remote("origin/feature", "f0"), gone])
        #expect(s.remoteTips == ["origin/main": "u2"])
        #expect(s.revisions == ["HEAD", "u2", "--tags"])
    }

    @Test("An upstream that is no remote branch adds nothing")
    func localUpstream() {
        let s = scope([GraphFixture.local("feature", "f", upstream: "main", ahead: 0, behind: 1),
                       GraphFixture.local("main", "m")])
        #expect(s.remoteTips.isEmpty)
        #expect(s.revisions == ["HEAD", "--tags"])
    }

    @Test("A remote trunk is always loaded")
    func remoteTrunk() {
        let s = scope([GraphFixture.local("feature", "f", head: true), GraphFixture.remote("origin/main", "m")],
                      trunks: ["origin/main": 0])
        #expect(s.remoteTips == ["origin/main": "m"])
    }

    @Test("With every remote branch, all their tips, each sha once")
    func allRemotes() {
        let s = scope([GraphFixture.remote("origin/a", "x"), GraphFixture.remote("origin/b", "y"),
                       GraphFixture.remote("fork/a", "x")], all: true)
        #expect(s.remoteTips.count == 3 && s.revisions == ["HEAD", "x", "y", "--tags"])
    }

    @Test("Outdated when a remote in scope moves, comes or goes, or the toggle flips; not when only local refs move")
    func outdated() {
        let loaded = scope([GraphFixture.local("main", "m", head: true, upstream: "origin/main", ahead: 0, behind: 1),
                            GraphFixture.remote("origin/main", "u2")])
        // A fetch moves origin/main.
        let moved = scope([GraphFixture.local("main", "m", head: true, upstream: "origin/main", ahead: 0, behind: 2),
                           GraphFixture.remote("origin/main", "u3")])
        #expect(loaded.isOutdated(by: moved))
        // A pull brings main up to origin/main, which leaves the scope.
        let pulled = scope([GraphFixture.local("main", "u2", head: true, upstream: "origin/main", ahead: 0, behind: 0),
                            GraphFixture.remote("origin/main", "u2")])
        #expect(loaded.isOutdated(by: pulled))
        // The toggle loads every remote branch.
        let all = scope([GraphFixture.local("main", "m", head: true, upstream: "origin/main", ahead: 0, behind: 1),
                         GraphFixture.remote("origin/main", "u2")], all: true)
        #expect(loaded.isOutdated(by: all))
        // A commit on main, still behind, plus a new branch and a stash: only local refs moved.
        let local = scope([GraphFixture.local("main", "m2", head: true, upstream: "origin/main", ahead: 1, behind: 1),
                           GraphFixture.remote("origin/main", "u2"), GraphFixture.local("topic", "t")],
                          unmerged: ["refs/heads/topic"], stashes: [Stash(index: 0, sha: "s1", subject: "WIP")])
        #expect(!loaded.isOutdated(by: local))
    }
}
