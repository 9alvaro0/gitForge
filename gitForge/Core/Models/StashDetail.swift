import Foundation

/// Extended view of a `Stash`: parent SHA + branch + author date + the list
/// of files touched compared to the parent (HEAD when stashed). File patches
/// are loaded lazily by the VM when the user selects a row.
nonisolated struct StashDetail: Sendable, Equatable {
    let stash: Stash
    let parentSha: String
    let parentBranch: String?
    let authorDate: Date?
    let files: [StashFileChange]
}

/// One file changed in a stash, compared to the stash's first parent.
nonisolated struct StashFileChange: Sendable, Equatable, Identifiable, Hashable {
    enum Status: Sendable, Equatable, Hashable {
        case added
        case modified
        case deleted
        case renamed
        case copied
        case typeChanged
        case other(String)
    }

    let path: String
    let oldPath: String?
    let status: Status
    let additions: Int
    let deletions: Int

    var id: String { (oldPath.map { "\($0)→" } ?? "") + path }
}

extension Stash {
    /// Branch name extracted from the reflog subject. Stashes are recorded as:
    ///   "WIP on <branch>: <hash> <commit-subject>"   (default)
    ///   "On <branch>: <user-message>"                (when -m is given)
    /// Returns nil for any other format we can't recognise.
    var parentBranch: String? {
        for prefix in ["WIP on ", "On "] where subject.hasPrefix(prefix) {
            let rest = subject.dropFirst(prefix.count)
            if let colon = rest.firstIndex(of: ":") {
                return String(rest[..<colon])
            }
        }
        return nil
    }
}
