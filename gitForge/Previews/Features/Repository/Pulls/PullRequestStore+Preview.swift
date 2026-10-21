import Foundation

@MainActor
extension PullRequestStore {
    /// Empty store that never hits the network (no token).
    static var preview: PullRequestStore {
        PullRequestStore(cli: GitCLI(workingDirectory: Repository.preview.url))
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

    /// The detail with review threads: under a line, resolved, outdated,
    /// and on a file the PR no longer lists.
    static var previewWithThreads: PullRequestStore {
        let store = previewWithDetail
        store.threads = [.previewOpen, .previewResolved, .previewOutdated, .previewElsewhere]
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

@MainActor
extension PullRequestStore {
    /// The merge sheet over a GitHub PR the host lets merge, options loaded.
    static var previewMergeGitHub: PullRequestStore {
        let store = previewWithDetail
        store.detail?.hostMergeStatus = HostMergeStatus(verdict: .ready)
        let options = MergeOptions(kind: .github(methods: [.squash, .merge, .rebase]), canDeleteSourceBranch: true,
                                   defaultsByMethod: [.squash: [.title: "Add pull request detail view (#42)"],
                                                      .merge: [.body: "Add pull request detail view"]],
                                   initialMethod: .squash, initialSquash: false)
        store.mergeOptions = options
        store.mergeDraft = MergeDraft(options: options)
        return store
    }

    /// The merge sheet over a GitLab MR whose project fast-forwards and
    /// always squashes.
    static var previewMergeGitLab: PullRequestStore {
        let store = previewMergeGitHub
        store.host = .previewGitLab
        let options = MergeOptions(kind: .gitlab(method: .fastForward, squash: .always), canDeleteSourceBranch: true,
                                   initialMethod: nil, initialSquash: true)
        store.mergeOptions = options
        store.mergeDraft = MergeDraft(options: options)
        return store
    }
}
