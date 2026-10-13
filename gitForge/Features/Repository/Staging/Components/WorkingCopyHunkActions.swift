import Foundation

extension DiffHunkActions {
    /// Hunk actions for `file`'s open side: Stage and Discard on the unstaged
    /// part, Unstage on the staged part. `nil` when the file can't take them
    /// (see `RepositoryViewModel.canApplyHunks(to:)`).
    @MainActor
    static func workingCopy(_ viewModel: RepositoryViewModel, file: WorkingCopyFile) -> DiffHunkActions? {
        guard viewModel.canApplyHunks(to: file) else { return nil }
        let staged = viewModel.workingCopy.diffSide(for: file) == .staged
        var actions = DiffHunkActions(
            verb: staged ? "Unstage" : "Stage",
            onApply: { hunk, lines in
                Task { await viewModel.apply(staged ? .unstage : .stage, hunk: hunk, lineIds: lines, in: file) }
            },
            disabled: viewModel.isMutating
        )
        if !staged {
            actions.onDiscard = { hunk, lines in
                Task { await viewModel.apply(.discard, hunk: hunk, lineIds: lines, in: file) }
            }
        }
        return actions
    }
}
