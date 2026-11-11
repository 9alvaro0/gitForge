import Foundation

/// One commit in a file's history (`git log --follow`): the commit, the
/// file's path in it and what the commit did to the file.
nonisolated struct FileHistoryEntry: Sendable, Equatable, Identifiable, Hashable {
    let commit: Commit
    /// The file's path in this commit, after the change. Older entries carry
    /// the names the file had before a rename.
    let path: String
    /// What the commit did to the file; `nil` when git printed no change for
    /// it (a merge that only brought it in from a side branch).
    let status: CommitFileChange.Status?

    var id: String { commit.sha }

    /// The path the file came from when this commit renamed or copied it.
    var previousPath: String? {
        switch status {
        case .renamed(let from), .copied(let from): from
        default: nil
        }
    }

    /// The commit deleted the file: there is nothing to blame at it.
    var isDeletion: Bool { status == .deleted }
}
