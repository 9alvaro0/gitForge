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
}
