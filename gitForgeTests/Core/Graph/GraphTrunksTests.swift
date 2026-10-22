import Foundation
import Testing
@testable import gitForge

@Suite("GraphTrunks")
struct GraphTrunksTests {

    @Test("origin/HEAD names the main trunk; develop by its name")
    func remoteHead() {
        let refs = [GraphFixture.local("feature", "f", head: true), GraphFixture.remote("origin/main", "m"),
                    GraphFixture.remote("origin/develop", "d")]
        #expect(GraphTrunks.remoteStandIns(refs: refs, remoteHeads: ["origin": "origin/main"])
                == ["origin/main": 0, "origin/develop": 1])
    }

    @Test("Without a remote HEAD: main, then master, then trunk")
    func fallbackNames() {
        let refs = [GraphFixture.remote("origin/trunk", "t"), GraphFixture.remote("origin/master", "m")]
        #expect(GraphTrunks.remoteStandIns(refs: refs, remoteHeads: [:]) == ["origin/master": 0])
    }

    @Test("A local trunk needs no stand-in", arguments: ["main", "master", "trunk"])
    func localTrunk(name: String) {
        let refs = [GraphFixture.local(name, "a"), GraphFixture.local("dev", "b"),
                    GraphFixture.remote("origin/main", "m"), GraphFixture.remote("origin/develop", "d")]
        #expect(GraphTrunks.remoteStandIns(refs: refs, remoteHeads: ["origin": "origin/main"]).isEmpty)
    }

    @Test("A remote HEAD on develop doesn't make develop the main trunk")
    func headOnDevelop() {
        let refs = [GraphFixture.remote("origin/main", "m"), GraphFixture.remote("origin/develop", "d")]
        #expect(GraphTrunks.remoteStandIns(refs: refs, remoteHeads: ["origin": "origin/develop"])
                == ["origin/main": 0, "origin/develop": 1])
    }

    /// A default branch `canary` checked out locally: `canary` tracking `origin/canary` (or only
    /// named like it), origin's HEAD on it, and `origin/main` when `withMain`.
    private static func canaryRefs(tracking: Bool, withMain: Bool) -> [GitRef] {
        [GraphFixture.local("canary", "c", head: true, upstream: tracking ? "origin/canary" : nil),
         GraphFixture.remote("origin/canary", "c")] + (withMain ? [GraphFixture.remote("origin/main", "m")] : [])
    }

    @Test("A remote HEAD on a branch that exists locally is no stand-in: origin/main is, if there is one",
          arguments: [true, false])
    func headOnLocalBranch(tracking: Bool) {
        let heads = ["origin": "origin/canary"]
        #expect(GraphTrunks.remoteStandIns(refs: Self.canaryRefs(tracking: tracking, withMain: true), remoteHeads: heads)
                == ["origin/main": 0])
        #expect(GraphTrunks.remoteStandIns(refs: Self.canaryRefs(tracking: tracking, withMain: false), remoteHeads: heads)
                .isEmpty)
    }

    @Test("A remote main or develop that a local branch tracks under another name is no stand-in; the next name is")
    func trackedFallbacks() {
        let refs = [GraphFixture.local("prod", "m", head: true, upstream: "origin/main"),
                    GraphFixture.local("integration", "d", upstream: "origin/develop"),
                    GraphFixture.remote("origin/main", "m"), GraphFixture.remote("origin/master", "o"),
                    GraphFixture.remote("origin/develop", "d"), GraphFixture.remote("origin/dev", "e")]
        #expect(GraphTrunks.remoteStandIns(refs: refs, remoteHeads: [:]) == ["origin/master": 0, "origin/dev": 1])
        #expect(GraphTrunks.remoteStandIns(refs: refs, remoteHeads: ["origin": "origin/main"])
                == ["origin/master": 0, "origin/dev": 1])
    }

    @Test("A remote HEAD on a branch of rank 2 to 4 that no local branch has stands in for main",
          arguments: ["release/2.0", "hotfix/crash", "canary"])
    func headOfOtherRank(branch: String) {
        let refs = [GraphFixture.local("feature", "f", head: true), GraphFixture.remote("origin/\(branch)", "b"),
                    GraphFixture.remote("origin/main", "m")]
        #expect(GraphTrunks.remoteStandIns(refs: refs, remoteHeads: ["origin": "origin/\(branch)"])
                == ["origin/\(branch)": 0])
    }

    @Test("With a local main but no local develop, only origin/develop stands in")
    func oneTrunkMissing() {
        let refs = [GraphFixture.local("main", "m", head: true, upstream: "origin/main"),
                    GraphFixture.remote("origin/main", "m"), GraphFixture.remote("origin/develop", "d")]
        #expect(GraphTrunks.remoteStandIns(refs: refs, remoteHeads: ["origin": "origin/main"]) == ["origin/develop": 1])
    }

    @Test("origin first; without it, the first remote by name")
    func whichRemote() {
        #expect(GraphTrunks.remoteStandIns(refs: [GraphFixture.remote("fork/main", "a"), GraphFixture.remote("origin/main", "b")],
                                           remoteHeads: [:]) == ["origin/main": 0])
        #expect(GraphTrunks.remoteStandIns(refs: [GraphFixture.remote("upstream/main", "a"), GraphFixture.remote("fork/main", "b")],
                                           remoteHeads: [:]) == ["fork/main": 0])
    }

    @Test("No remote branches, no stand-ins")
    func noRemotes() {
        #expect(GraphTrunks.remoteStandIns(refs: [GraphFixture.local("feature", "f")], remoteHeads: ["origin": "origin/main"]).isEmpty)
    }
}
