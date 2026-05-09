import Foundation

extension PullRequest {
    static let previewSamples: [PullRequest] = [
        PullRequest(
            id: "1",
            number: 42,
            title: "Add merge request integration",
            state: .open,
            authorLogin: "9alvaro0",
            authorAvatarURL: nil,
            sourceBranch: "feature/mr-integration",
            targetBranch: "main",
            webURL: URL(string: "https://github.com/9alvaro0/gitForge/pull/42"),
            createdAt: Date(timeIntervalSinceNow: -3600 * 24 * 2),
            updatedAt: Date(timeIntervalSinceNow: -3600 * 5)
        ),
        PullRequest(
            id: "2",
            number: 41,
            title: "Resizable diff pane",
            state: .merged,
            authorLogin: "9alvaro0",
            authorAvatarURL: nil,
            sourceBranch: "feat/diff-pane",
            targetBranch: "main",
            webURL: URL(string: "https://github.com/9alvaro0/gitForge/pull/41"),
            createdAt: Date(timeIntervalSinceNow: -3600 * 24 * 5),
            updatedAt: Date(timeIntervalSinceNow: -3600 * 24 * 1)
        ),
        PullRequest(
            id: "3",
            number: 40,
            title: "WIP: graph perf",
            state: .draft,
            authorLogin: "9alvaro0",
            authorAvatarURL: nil,
            sourceBranch: "feat/graph-perf",
            targetBranch: "main",
            webURL: nil,
            createdAt: Date(timeIntervalSinceNow: -3600 * 24 * 3),
            updatedAt: Date(timeIntervalSinceNow: -3600 * 12)
        ),
    ]
}
