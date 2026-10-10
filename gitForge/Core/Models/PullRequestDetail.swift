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
        enum State: Sendable, Equatable, Hashable {
            case approved, changesRequested, pending
        }

        let login: String
        let state: State
        var id: String { login }
        var approved: Bool { state == .approved }
    }
}

/// One CI job: a GitHub check run or commit status, or a GitLab job.
nonisolated struct CICheck: Sendable, Equatable, Identifiable {
    enum State: Sendable, Equatable {
        case passed, failed, running, queued, skipped, canceled

        var label: String {
            switch self {
            case .passed: "Passed"
            case .failed: "Failed"
            case .running: "Running"
            case .queued: "Queued"
            case .skipped: "Skipped"
            case .canceled: "Canceled"
            }
        }
    }

    let name: String
    /// Where it runs: the GitHub app ("GitHub Actions") or the GitLab stage.
    let context: String?
    let state: State
    let duration: TimeInterval?
    /// Why it failed, when the provider says (check-run title, GitLab
    /// failure reason, status description).
    let failureMessage: String?
    let webURL: URL?

    var id: String { "\(context ?? "")/\(name)" }
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

    /// One state for a set of checks: any failure fails it; otherwise
    /// anything still running or queued keeps it pending; otherwise it
    /// passes if something passed. Skipped / canceled alone say nothing.
    static func summarize(_ checks: [CICheck], webURL: URL? = nil) -> CIStatus? {
        guard !checks.isEmpty else { return nil }
        let states = checks.map(\.state)
        let state: State
        if states.contains(.failed) {
            state = .failure
        } else if states.contains(.running) || states.contains(.queued) {
            state = .pending
        } else if states.contains(.passed) {
            state = .success
        } else if states.contains(.canceled) {
            state = .canceled
        } else {
            state = .unknown
        }
        let failing = checks.first { $0.state == .failed }
        return CIStatus(state: state, description: nil, webURL: failing?.webURL ?? webURL ?? checks.first?.webURL)
    }

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
