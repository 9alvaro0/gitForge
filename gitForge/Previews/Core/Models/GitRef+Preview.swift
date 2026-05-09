import Foundation

extension GitRef {
    static let previewSamples: [GitRef] = [
        GitRef(name: "main", kind: .localBranch, targetSha: "a1b2c3d4e5f6789012345678901234567890abcd", isHead: true),
        GitRef(name: "feature/working-copy", kind: .localBranch, targetSha: "b2c3d4e5f6789012345678901234567890abcdab", isHead: false),
        GitRef(name: "fix/pipe-deadlock", kind: .localBranch, targetSha: "c3d4e5f6789012345678901234567890abcdabcd", isHead: false),
        GitRef(name: "origin/main", kind: .remoteBranch(remote: "origin"), targetSha: "a1b2c3d4e5f6789012345678901234567890abcd", isHead: false),
        GitRef(name: "origin/feature/working-copy", kind: .remoteBranch(remote: "origin"), targetSha: "b2c3d4e5f6789012345678901234567890abcdab", isHead: false),
        GitRef(name: "v0.1.0", kind: .tag, targetSha: "e5f6789012345678901234567890abcdabcdef12", isHead: false),
    ]

    // MARK: Single refs (per-row previews)

    static let previewLocalMain = GitRef(
        name: "main", kind: .localBranch,
        targetSha: "a1b2c3d4e5f6789012345678901234567890abcd", isHead: true
    )
    static let previewLocalFeature = GitRef(
        name: "feature/awesome", kind: .localBranch,
        targetSha: "deadbeef0000000000000000000000000000beef", isHead: false
    )
    static let previewRemoteMain = GitRef(
        name: "origin/main", kind: .remoteBranch(remote: "origin"),
        targetSha: "a1b2c3d4e5f6789012345678901234567890abcd", isHead: false
    )
    static let previewTag = GitRef(
        name: "v1.2.3", kind: .tag,
        targetSha: "e5f6789012345678901234567890abcdabcdef12", isHead: false
    )

    // MARK: Collections (section previews)

    /// Locals with nested folder paths so the tree builder has something
    /// hierarchical to render — exercises folder collapse + multiple depths.
    static let previewLocalNested: [GitRef] = [
        previewLocalMain,
        GitRef(name: "feature/awesome", kind: .localBranch,
               targetSha: "b2c3d4e5f6789012345678901234567890abcdab", isHead: false),
        GitRef(name: "feature/repository/branches", kind: .localBranch,
               targetSha: "c3d4e5f6789012345678901234567890abcdabcd", isHead: false),
        GitRef(name: "release/2026.05", kind: .localBranch,
               targetSha: "d4e5f6789012345678901234567890abcdabcdef", isHead: false),
    ]

    /// Tag list used by the FlowLayout preview in `BranchTagsSection`.
    static let previewTagSamples: [GitRef] = (1...8).map { i in
        GitRef(name: "v1.\(i).0", kind: .tag,
               targetSha: String(repeating: "0", count: 39) + "\(i)", isHead: false)
    }
}
