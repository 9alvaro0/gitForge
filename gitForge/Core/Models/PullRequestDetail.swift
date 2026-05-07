import Foundation

/// Extended view of a `PullRequest`: description, reviewers, labels, mergeability
/// and CI status. Fetched on-demand when the user opens a row.
nonisolated struct PullRequestDetail: Sendable, Equatable {
    let pull: PullRequest
    let descriptionMarkdown: String?
    let labels: [String]
    let reviewers: [Reviewer]
    let assignees: [String]
    /// Provider's mergeability hint. `nil` when unknown / still computing.
    let mergeable: Bool?
    let ciStatus: CIStatus?

    struct Reviewer: Sendable, Equatable, Identifiable, Hashable {
        let login: String
        let approved: Bool
        var id: String { login }
    }
}

/// Continuous integration status summary.
nonisolated struct CIStatus: Sendable, Equatable {
    enum State: Sendable, Equatable {
        case success
        case failure
        case pending
        case canceled
        case unknown
    }
    let state: State
    let description: String?
    let webURL: URL?

    var label: String {
        switch state {
        case .success:  "Passing"
        case .failure:  "Failing"
        case .pending:  "Running"
        case .canceled: "Canceled"
        case .unknown:  "Unknown"
        }
    }
}

/// One commit in a PR/MR.
nonisolated struct PullRequestCommit: Sendable, Equatable, Identifiable {
    let sha: String
    let subject: String
    let authorName: String?
    let authorDate: Date?

    var id: String { sha }
    var shortSha: String { String(sha.prefix(7)) }
}

/// A file changed in a PR/MR. `patch` is the unified diff (parseable with
/// `DiffParser`) — may be nil when the provider omits it (binary / very
/// large changes).
nonisolated struct PullRequestFileChange: Sendable, Equatable, Identifiable {
    enum Status: Sendable, Equatable {
        case added
        case modified
        case deleted
        case renamed
        case copied
        case other(String)
    }

    let path: String
    let oldPath: String?     // populated for renames
    let status: Status
    let additions: Int
    let deletions: Int
    let patch: String?

    var id: String { (oldPath.map { "\($0)→" } ?? "") + path }
}
