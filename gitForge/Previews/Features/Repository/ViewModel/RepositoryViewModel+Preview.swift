import Foundation

@MainActor
extension RepositoryViewModel {
    static var preview: RepositoryViewModel {
        let vm = RepositoryViewModel(repository: Repository.preview)
        vm.commits = Commit.previewSamples
        vm.selectedCommitId = Commit.previewSamples.first?.id
        vm.detailCache[Commit.preview.sha] = CommitDetail.preview
        vm.refs = GitRef.previewSamples
        vm.currentBranchName = "main"
        vm.status = WorkingCopyStatus.preview
        vm.recomputeGraph()
        return vm
    }

    /// Variant in the middle of a merge with parsed hunks ready to pick —
    /// used by ConflictView and its column previews.
    static var previewWithConflicts: RepositoryViewModel {
        let vm = preview
        vm.mergeState = .merging
        vm.conflictFiles = ConflictFile.previewSamples
        vm.selectedConflictPath = ConflictFile.previewSamples.first?.path
        vm.conflictHunks = ConflictHunk.previewSamples
        if let firstHunk = ConflictHunk.previewSamples.first {
            vm.conflictPicks = [firstHunk.id: .ours]
        }
        return vm
    }

    /// Variant with a populated PR list against a GitHub host.
    static var previewWithPullRequests: RepositoryViewModel {
        let vm = preview
        vm.pullRequests = PullRequest.previewSamples
        vm.pullRequestsHost = .previewGitHub
        return vm
    }

    /// Variant with the user already drilled into a single PR, with detail /
    /// commits / files all populated.
    static var previewWithPullRequestDetail: RepositoryViewModel {
        let vm = previewWithPullRequests
        vm.selectedPullRequest = PullRequest.previewSamples.first
        vm.pullRequestDetail = PullRequestDetail.previewSample
        vm.pullRequestCommits = PullRequestCommit.previewSamples
        vm.pullRequestFiles = PullRequestFileChange.previewSamples
        return vm
    }

    /// Variant mid-load on the PR list (no detail yet).
    static var previewLoadingPullRequest: RepositoryViewModel {
        let vm = previewWithPullRequests
        vm.selectedPullRequest = PullRequest.previewSamples.first
        vm.pullRequestDetailLoading = true
        return vm
    }

    /// Empty status that hasn't finished its first refresh — drives the
    /// staging skeleton.
    static var previewLoadingStatus: RepositoryViewModel {
        let vm = preview
        vm.status = WorkingCopyStatus(files: [])
        vm.hasLoadedStatusOnce = false
        return vm
    }

    /// Empty status with the first refresh completed — drives the
    /// "Working tree is clean" empty state.
    static var previewCleanTree: RepositoryViewModel {
        let vm = preview
        vm.status = WorkingCopyStatus(files: [])
        vm.hasLoadedStatusOnce = true
        return vm
    }
}
