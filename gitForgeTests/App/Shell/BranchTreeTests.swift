import Foundation
import Testing
@testable import gitForge

@Suite("BranchTree")
struct BranchTreeTests {

    private static func local(_ name: String, head: Bool = false) -> GitRef {
        GitRef(name: name, kind: .localBranch, targetSha: "sha-\(name)", isHead: head)
    }

    private static func summary(_ rows: [BranchTreeRow]) -> [String] {
        rows.map { row in
            let indent = String(repeating: "  ", count: row.depth)
            switch row.kind {
            case .folder(_, let expanded): return "\(indent)\(row.name)/\(expanded ? "" : " (collapsed)")"
            case .branch: return "\(indent)\(row.name)\(row.containsHead ? " *" : "")"
            }
        }
    }

    @Test("Slash-separated names nest under folders; folders sort before branches")
    func nesting() {
        let refs = [Self.local("main", head: true), Self.local("feature/b"), Self.local("feature/a"), Self.local("fix/ssh/timeout")]
        #expect(Self.summary(BranchTree.rows(for: refs, collapsed: [])) == [
            "feature/", "  a", "  b",
            "fix/", "  ssh/", "    timeout",
            "main *",
        ])
    }

    @Test("Sorting is natural and case-insensitive")
    func naturalSort() {
        let refs = [Self.local("release/1.10"), Self.local("release/1.9"), Self.local("Zeta"), Self.local("alpha")]
        #expect(Self.summary(BranchTree.rows(for: refs, collapsed: [])) == [
            "release/", "  1.9", "  1.10", "alpha", "Zeta",
        ])
    }

    @Test("A collapsed folder hides its descendants and reports collapsed")
    func collapsed() {
        let refs = [Self.local("feature/a"), Self.local("feature/deep/b"), Self.local("main")]
        #expect(Self.summary(BranchTree.rows(for: refs, collapsed: ["feature"])) == [
            "feature/ (collapsed)", "main",
        ])
        #expect(Self.summary(BranchTree.rows(for: refs, collapsed: ["feature/deep"])) == [
            "feature/", "  deep/ (collapsed)", "  a", "main",
        ])
    }

    @Test("A folder that holds HEAD says so, so a collapsed tree still shows where HEAD is")
    func folderContainsHead() {
        let rows = BranchTree.rows(for: [Self.local("feature/x", head: true)], collapsed: ["feature"])
        #expect(rows.count == 1)
        #expect(rows[0].containsHead)
    }

    @Test("Remote branches and tags are ignored; no locals gives no rows")
    func onlyLocals() {
        let refs = [
            GitRef(name: "origin/main", kind: .remoteBranch(remote: "origin"), targetSha: "a", isHead: false),
            GitRef(name: "v1.0", kind: .tag, targetSha: "b", isHead: false),
        ]
        #expect(BranchTree.rows(for: refs, collapsed: []).isEmpty)
        #expect(BranchTree.rows(for: [], collapsed: []).isEmpty)
    }

    @Test("Row ids are unique and stable")
    func ids() {
        let refs = [Self.local("feature/a"), Self.local("feature/b")]
        let rows = BranchTree.rows(for: refs, collapsed: [])
        #expect(Set(rows.map(\.id)).count == rows.count)
        #expect(rows.map(\.id) == BranchTree.rows(for: refs.reversed(), collapsed: []).map(\.id))
    }

    @Test("Remote names are unique and sorted")
    func remoteNames() {
        let refs = [
            GitRef(name: "upstream/main", kind: .remoteBranch(remote: "upstream"), targetSha: "a", isHead: false),
            GitRef(name: "origin/main", kind: .remoteBranch(remote: "origin"), targetSha: "a", isHead: false),
            GitRef(name: "origin/dev", kind: .remoteBranch(remote: "origin"), targetSha: "b", isHead: false),
            Self.local("main"),
        ]
        #expect(BranchTree.remoteNames(in: refs) == ["origin", "upstream"])
    }
}
