import Foundation

/// The local work git said was in the way when it refused to pull.
nonisolated enum BlockingLocalChanges: Sendable, Equatable {
    /// Merge / fast-forward: the paths git listed — tracked changes (staged
    /// or not) and untracked files the incoming commits would overwrite.
    case paths([String])
    /// Rebase refuses over any tracked change, staged or not, and names none.
    case allTrackedChanges

    init?(stderr: String) {
        if stderr.contains("cannot pull with rebase: You have unstaged changes")
            || stderr.contains("cannot pull with rebase: Your index contains uncommitted changes") {
            self = .allTrackedChanges
            return
        }
        // Each list follows a "… would be overwritten by …:" header, one
        // tab-indented path per line; anything else ends it. Only the tab
        // is git's: the rest of the line is the path, spaces included.
        var paths: [String] = []
        var inList = false
        for line in stderr.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.contains("would be overwritten by") {
                inList = true
            } else if inList, line.hasPrefix("\t") {
                paths.append(String(line.dropFirst()))
            } else {
                inList = false
            }
        }
        guard !paths.isEmpty else { return nil }
        self = .paths(paths)
    }

    init?(error: Error) {
        guard case .commandFailed(_, _, let stderr)? = error as? GitError else { return nil }
        self.init(stderr: stderr)
    }
}
