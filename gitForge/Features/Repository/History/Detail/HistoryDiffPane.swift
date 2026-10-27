import SwiftUI

/// The diff History shows for its selection: the selected commit file's, or
/// the working copy's when "Uncommitted changes" is selected (with the hunk
/// actions of Changes). Used in the inspector and in the expanded diff.
struct HistoryDiffPane: View {
    @Bindable var viewModel: RepositoryViewModel
    let isUncommittedSelected: Bool
    let diffMode: Binding<DiffPane.ViewMode>
    /// Hides the pane; `nil` offers no close button.
    var onClose: (() -> Void)? = nil
    var isExpanded = false
    var onToggleExpand: (() -> Void)? = nil

    var body: some View {
        // Two branches, so each mode keeps a single `DiffPane` (and its
        // tokenisation cache) across selection changes.
        if isUncommittedSelected {
            DiffPane(
                file: viewModel.workingCopy.selectedWorkingCopyFile?.path,
                status: viewModel.workingCopy.selectedWorkingCopyFile.map { StatusTag.Kind(workingFile: $0.displayStatus) },
                hunks: viewModel.workingCopy.workingCopyDiff,
                loading: viewModel.workingCopy.loadingWorkingCopyDiff,
                emptyState: viewModel.workingCopy.workingCopyDiffEmptyState,
                onClose: onClose,
                onWhitespaceChange: { Task { await viewModel.workingCopy.reloadSelectedDiff() } },
                hunkActions: viewModel.workingCopy.selectedWorkingCopyFile.flatMap {
                    DiffHunkActions.workingCopy(viewModel, file: $0)
                },
                loadNewSide: viewModel.workingCopy.selectedWorkingCopyFile.map { file -> () async -> [String]? in
                    { await viewModel.workingCopy.newSideLines(for: file) }
                },
                isExpanded: isExpanded,
                onToggleExpand: onToggleExpand,
                viewMode: diffMode
            )
        } else {
            DiffPane(
                file: viewModel.history.selectedCommitFile,
                status: selectedCommitFileStatus,
                hunks: viewModel.history.commitFileDiff,
                loading: viewModel.history.loadingCommitFileDiff,
                emptyState: viewModel.history.commitFileDiffEmptyState,
                onClose: onClose,
                onWhitespaceChange: { Task { await viewModel.history.reloadCommitFileDiff() } },
                loadNewSide: commitFileLoader,
                isExpanded: isExpanded,
                onToggleExpand: onToggleExpand,
                viewMode: diffMode
            )
        }
    }

    /// The selected commit file's content at that commit, for hidden lines.
    private var commitFileLoader: (() async -> [String]?)? {
        guard let sha = viewModel.history.selectedCommit?.sha,
              let path = viewModel.history.selectedCommitFile else { return nil }
        let cli = viewModel.cli
        return { await cli.fileLines(revision: sha, path: path) }
    }

    /// Badge for the commit file in the diff header, once the detail is loaded.
    private var selectedCommitFileStatus: StatusTag.Kind? {
        guard let sha = viewModel.history.selectedCommit?.sha,
              let path = viewModel.history.selectedCommitFile,
              let file = viewModel.history.detailCache[sha]?.files.first(where: { $0.path == path }) else { return nil }
        return StatusTag.Kind(commitFile: file.status)
    }
}
