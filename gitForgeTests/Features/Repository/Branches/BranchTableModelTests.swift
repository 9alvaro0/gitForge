import CoreGraphics
import Testing
@testable import gitForge

@Suite("Branches & Tags table model")
struct BranchTableModelTests {

    private static func local(_ name: String) -> GitRef {
        GitRef(name: name, kind: .localBranch, targetSha: "a", isHead: false)
    }

    @Test("Each scope lists only its kind of ref")
    func scopes() {
        let remote = GitRef(name: "origin/main", kind: .remoteBranch(remote: "origin"), targetSha: "a", isHead: false)
        let tag = GitRef(name: "v1", kind: .tag, targetSha: "a", isHead: false)
        #expect(BranchScope.local.includes(Self.local("x")) && !BranchScope.local.includes(remote))
        #expect(BranchScope.remote.includes(remote) && !BranchScope.remote.includes(tag))
        #expect(BranchScope.tags.includes(tag) && !BranchScope.tags.includes(Self.local("x")))
    }

    @Test("HEAD takes the accent; trunks keep their graph lanes; the rest stay neutral")
    func glyphColors() {
        #expect(BranchGlyphColor.of(Self.local("main"), currentBranch: "main") == .accent)
        #expect(BranchGlyphColor.of(Self.local("main"), currentBranch: "dev") == .lane(.lane0))
        #expect(BranchGlyphColor.of(Self.local("master"), currentBranch: nil) == .lane(.lane0))
        #expect(BranchGlyphColor.of(Self.local("develop"), currentBranch: nil) == .lane(.lane3))
        #expect(BranchGlyphColor.of(Self.local("feature/x"), currentBranch: nil) == .neutral)
        let remoteMain = GitRef(name: "origin/main", kind: .remoteBranch(remote: "origin"), targetSha: "a", isHead: false)
        #expect(BranchGlyphColor.of(remoteMain, currentBranch: "main") == .lane(.lane0))
        let tag = GitRef(name: "main", kind: .tag, targetSha: "a", isHead: false)
        #expect(BranchGlyphColor.of(tag, currentBranch: nil) == .neutral)
    }

    @Test("Wide tables show the full subject column")
    func wide() {
        let layout = BranchTableLayout(width: 784, scope: .local)
        #expect(layout.upstream == 110 && layout.subject == 250 && layout.updated == 84 && layout.commit == 0)
    }

    @Test("The subject shrinks, then hides, as the table narrows")
    func narrow() {
        let mid = BranchTableLayout(width: 640, scope: .local)
        #expect(mid.subject > 160 && mid.subject < 250)
        #expect(BranchTableLayout(width: 560, scope: .local).subject == 0)
        // Remote has no upstream column, so the same width keeps a subject.
        #expect(BranchTableLayout(width: 560, scope: .remote).subject == 200)
    }

    @Test("Only local shows the upstream column; only tags show the commit column")
    func scopeColumns() {
        #expect(BranchTableLayout(width: 900, scope: .remote).upstream == 0)
        #expect(BranchTableLayout(width: 900, scope: .tags).commit == 72)
        #expect(BranchTableLayout(width: 900, scope: .tags).upstream == 0)
    }
}
