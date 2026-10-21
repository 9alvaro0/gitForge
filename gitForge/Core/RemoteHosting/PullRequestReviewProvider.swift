import Foundation

/// A review's outcome on the host.
nonisolated enum ReviewVerdict: Sendable, Equatable, Hashable {
    case approve, requestChanges
}

/// Whether the host can take "Request changes" from the API.
nonisolated enum RequestChangesSupport: Sendable, Equatable {
    case supported
    case unsupported(reason: String)
}

/// The signed-in user's standing on a GitLab MR (`/approvals`).
nonisolated struct ViewerApproval: Sendable, Equatable {
    let canApprove: Bool
    let hasApproved: Bool
}

/// The writes on a PR/MR, apart from `PullRequestProvider` so its read-only
/// doubles stay as they are.
protocol PullRequestReviewProvider: Sendable {
    func requestChangesSupport(host: RemoteHost, token: String) async -> RequestChangesSupport

    /// Approves or requests changes, with `body` as the review comment.
    /// Returns a warning when the verdict landed but its comment didn't.
    func submitReview(host: RemoteHost, pull: PullRequest, verdict: ReviewVerdict,
                      body: String, token: String) async throws -> String?
}
