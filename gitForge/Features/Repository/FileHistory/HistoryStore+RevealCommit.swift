import Foundation

extension HistoryStore {
    /// How deep `revealCommit` pages before giving up.
    static let revealCommitDepth = 20_000

    /// Selects `sha` in History, loading pages of the log until it shows up
    /// (History's table scrolls to the selection). `false`, leaving the
    /// selection alone, when it isn't in History's scope within
    /// `revealCommitDepth` commits, or a page couldn't be read.
    func revealCommit(_ sha: String) async -> Bool {
        if commits.isEmpty { await loadInitial() }
        while commitsById[sha] == nil, hasMore, commits.count < Self.revealCommitDepth,
              let last = commits.last {
            await loadMoreIfNeeded(currentItem: last)
            // Nothing new: a page already loading, or one that failed.
            if commits.last == last { break }
        }
        guard commitsById[sha] != nil else { return false }
        selectedCommitId = sha
        return true
    }
}
