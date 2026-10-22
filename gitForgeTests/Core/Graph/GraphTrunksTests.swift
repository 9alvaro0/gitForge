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
