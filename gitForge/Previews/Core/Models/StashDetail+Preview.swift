import Foundation

extension StashFileChange {
    static let previewSamples: [StashFileChange] = [
        .init(path: "Sources/Foo.swift", oldPath: nil, status: .modified, additions: 12, deletions: 4),
        .init(path: "Sources/NewService.swift", oldPath: nil, status: .added, additions: 86, deletions: 0),
        .init(path: "README.md", oldPath: nil, status: .modified, additions: 2, deletions: 1),
        .init(path: "Sources/Old/Path.swift", oldPath: nil, status: .deleted, additions: 0, deletions: 24),
        .init(
            path: "Sources/Features/Repository/Renamed.swift",
            oldPath: "Sources/Old/Path.swift",
            status: .renamed, additions: 3, deletions: 3
        ),
    ]
}

extension StashDetail {
    static let previewSample = StashDetail(
        stash: Stash.previewSamples[0],
        parentSha: "deadbeefcafebabe1234567890abcdef",
        parentBranch: Stash.previewSamples[0].parentBranch ?? "main",
        authorDate: Date(timeIntervalSinceNow: -3600 * 4),
        files: StashFileChange.previewSamples
    )
}
