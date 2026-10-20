import Foundation

/// How much of a Staged / Unstaged section is ticked for a batch action.
/// Drives the section header's select-all checkbox (mixed when partial).
nonisolated enum StagingSectionSelection: Equatable, Sendable {
    case empty
    case partial(Int)
    case full

    init(paths: [String], selected: Set<String>) {
        let count = paths.lazy.filter(selected.contains).count
        if count == 0 {
            self = .empty
        } else if count == paths.count {
            self = .full
        } else {
            self = .partial(count)
        }
    }

    /// Ticked files in the section.
    func count(of total: Int) -> Int {
        switch self {
        case .empty: 0
        case .partial(let n): n
        case .full: total
        }
    }
}

/// Title of the composer's primary button.
nonisolated enum CommitButtonTitle {
    static func make(fileCount: Int, branch: String?, amend: Bool) -> String {
        if amend { return String(localized: "Amend last commit") }
        guard let branch else { return String(localized: "Commit to detached HEAD") }
        return fileCount == 1
            ? String(localized: "Commit 1 file to \(branch)")
            : String(localized: "Commit \(fileCount) files to \(branch)")
    }
}
