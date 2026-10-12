import Foundation
import Testing
@testable import gitForge

@Suite("SidebarHost — when to read remotes again")
struct SidebarHostRemotesTests {
    @Test("The remotes that have tracking branches, so a new remote's first fetch changes the key")
    func remoteNames() {
        let refs = [
            GitRef(name: "main", kind: .localBranch, targetSha: "a", isHead: true),
            GitRef(name: "origin/main", kind: .remoteBranch(remote: "origin"), targetSha: "a", isHead: false),
            GitRef(name: "origin/dev", kind: .remoteBranch(remote: "origin"), targetSha: "b", isHead: false),
            GitRef(name: "upstream/main", kind: .remoteBranch(remote: "upstream"), targetSha: "a", isHead: false),
            GitRef(name: "v1", kind: .tag, targetSha: "a", isHead: false),
        ]
        #expect(SidebarHost.remoteNames(refs) == ["origin", "upstream"])
    }
}
