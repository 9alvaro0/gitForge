import Foundation

@MainActor
extension PullRequestStore {
    /// Empty store that never hits the network (no token).
    static var preview: PullRequestStore {
        PullRequestStore(cli: GitCLI(workingDirectory: Repository.preview.url), token: { _ in nil })
    }

    /// Populated PR list against a GitHub host.
    static var previewWithPullRequests: PullRequestStore {
        let store = preview
        store.items = PullRequest.previewSamples
        store.host = .previewGitHub
        return store
    }

    /// Drilled into a single PR with detail / commits / files populated.
    static var previewWithDetail: PullRequestStore {
        let store = previewWithPullRequests
        store.selected = PullRequest.previewSamples.first
        store.detail = PullRequestDetail.previewSample
        store.commits = PullRequestCommit.previewSamples
        store.files = PullRequestFileChange.previewSamples
        return store
    }

    /// Drilled into a PR whose detail is still loading.
    static var previewLoadingDetail: PullRequestStore {
        let store = previewWithPullRequests
        store.selected = PullRequest.previewSamples.first
        store.isLoadingDetail = true
        return store
    }
}
