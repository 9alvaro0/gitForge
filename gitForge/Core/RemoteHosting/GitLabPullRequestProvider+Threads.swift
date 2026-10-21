import Foundation

/// Diff discussions on GitLab, as review threads.
extension GitLabPullRequestProvider {
    func fetchThreads(host: RemoteHost, pull: PullRequest, detail: PullRequestDetail?, token: String) async throws -> [ReviewThread] {
        []
    }
}
