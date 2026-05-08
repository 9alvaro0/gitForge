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
}
