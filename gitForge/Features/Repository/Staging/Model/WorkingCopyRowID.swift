import Foundation

/// One row of a Staged / Unstaged file list. A file with changes on both
/// sides appears in each list, so the path alone isn't unique.
nonisolated struct WorkingCopyRowID: Hashable, Sendable {
    let side: WorkingCopySide
    let path: String
}

extension WorkingCopyStore {
    /// The row whose diff is open, for keyboard navigation.
    var selectedRowID: WorkingCopyRowID? {
        selectedWorkingCopyFile.map { WorkingCopyRowID(side: diffSide(for: $0), path: $0.path) }
    }

    /// Opens the row `id` names, if its file is still in `files`.
    func select(_ id: WorkingCopyRowID, in files: [WorkingCopyFile]) {
        guard let file = files.first(where: { $0.path == id.path }) else { return }
        select(file, side: id.side)
    }
}
