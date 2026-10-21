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

    /// The methods, squash policy and message defaults the merge sheet
    /// offers, read when it opens.
    func fetchMergeOptions(host: RemoteHost, pull: PullRequest, detail: PullRequestDetail,
                           commits: [PullRequestCommit], token: String) async throws -> MergeOptions

    /// Merges with `input`, then deletes the source branch if asked. A
    /// failed deletion doesn't undo the merge: it comes back as `branchDeleted == false`.
    func merge(host: RemoteHost, pull: PullRequest, input: MergeInput, token: String) async throws -> MergeOutcome

    /// The review threads on the PR's lines. `detail` gives GitLab the
    /// current head, which tells outdated threads apart.
    func fetchThreads(host: RemoteHost, pull: PullRequest, detail: PullRequestDetail?, token: String) async throws -> [ReviewThread]

    /// Posts `body` on `target`'s line, published right away. Pinned to the
    /// head shown (`detail`'s, else `pull`'s): without one it throws
    /// `PullRequestActionError.headChanged` and sends nothing.
    func addComment(host: RemoteHost, pull: PullRequest, detail: PullRequestDetail?, target: CommentTarget,
                    body: String, token: String) async throws

    /// Answers `thread` with `body`.
    func reply(host: RemoteHost, pull: PullRequest, thread: ReviewThread, body: String, token: String) async throws

    /// Resolves (`true`) or reopens `thread`.
    func setResolved(_ resolved: Bool, host: RemoteHost, pull: PullRequest, thread: ReviewThread, token: String) async throws
}

/// Resolves the review writes for a `RemoteHost`.
enum PullRequestReviewProviderFactory {
    static func make(for host: RemoteHost) -> PullRequestReviewProvider {
        switch host.provider {
        case .github: GitHubPullRequestProvider()
        case .gitlab: GitLabPullRequestProvider()
        }
    }
}
