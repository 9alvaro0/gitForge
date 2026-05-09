import Foundation

extension CIStatus {
    static let previewSamples: [CIStatus] = [
        .init(state: .success, description: "All checks passed", webURL: nil),
        .init(state: .failure, description: "1 check failed", webURL: nil),
        .init(state: .pending, description: "Running…", webURL: nil),
    ]
}

extension PullRequestCommit {
    static let previewSamples: [PullRequestCommit] = [
        .init(sha: "abc1234abcdef", subject: "feat: add pull request detail view",
              authorName: "9alvaro0", authorDate: Date(timeIntervalSinceNow: -3600)),
        .init(sha: "def5678abcdef", subject: "refactor: split provider-specific mappers",
              authorName: "9alvaro0", authorDate: Date(timeIntervalSinceNow: -7200)),
        .init(sha: "fab9012abcdef", subject: "fix: handle nil reviewer avatar URLs",
              authorName: "9alvaro0", authorDate: Date(timeIntervalSinceNow: -10800)),
        .init(sha: "abc3456abcdef", subject: "chore: bump dependency versions",
              authorName: "9alvaro0", authorDate: Date(timeIntervalSinceNow: -14400)),
        .init(sha: "fed7890abcdef", subject: "test: cover empty merge request payloads",
              authorName: "9alvaro0", authorDate: Date(timeIntervalSinceNow: -18000)),
    ]
}

extension PullRequestFileChange {
    static let previewSamples: [PullRequestFileChange] = [
        .init(
            path: "Sources/Foo.swift", oldPath: nil, status: .modified,
            additions: 42, deletions: 5,
            patch: "@@ -1,3 +1,5 @@\n line1\n-old\n+new\n+added\n line3"
        ),
        .init(
            path: "README.md", oldPath: nil, status: .added,
            additions: 10, deletions: 0,
            patch: "@@ -0,0 +1,3 @@\n+# Title\n+\n+Body"
        ),
    ]
}

extension PullRequestDetail {
    static let previewSample = PullRequestDetail(
        pull: PullRequest.previewSamples[0],
        descriptionMarkdown:
            "Adds the **PR/MR** integration with `Phase 2` detail view.\n\n- Description\n- Commits\n- Files",
        labels: ["feature", "phase-2"],
        reviewers: [
            .init(login: "reviewer1", approved: true),
            .init(login: "reviewer2", approved: false),
        ],
        assignees: ["9alvaro0"],
        mergeable: true,
        ciStatus: CIStatus(state: .success, description: "All checks passed", webURL: nil)
    )
}
