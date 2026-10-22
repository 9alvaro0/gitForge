import Foundation

/// What ⌘K reads from the inbox and what it does to it (R2 Rulings 6 to 8):
/// the pull requests to search, the followed repos that aren't cloned, the
/// filter by repo and picking a row from outside the list.
extension ReviewsStore {
    /// The repo `repoFilter` names, while it's still followed.
    var filteredRepo: ReviewRepo? {
        guard let repoFilter else { return nil }
        return repos.first { $0.id == repoFilter }
    }

    /// Every open pull request of the followed repos, newest first: both
    /// halves, drafts included, whatever the filters show. What the palette
    /// searches (Ruling 5).
    var searchablePulls: [InboxPull] {
        followedRows.sorted { Self.newerFirst($0.pull, $1.pull) }
    }

    /// The followed repos with no clone on this Mac, in `repos` order
    /// (Ruling 6).
    var unclonedRepos: [ReviewRepo] {
        repos.filter { $0.localURL == nil }
    }

    /// Selects `id` from outside the list (Ruling 8). The inbox moves to the
    /// half that shows its row, Mine if it's the user's and Team if not, and
    /// drops the filter by a repo other than its own. `false`, with nothing
    /// changed, when `id` isn't a row.
    @discardableResult
    func reveal(_ id: InboxPull.ID) -> Bool {
        guard let item = followedRows.first(where: { $0.id == id }) else { return false }
        filter = isMine(item.pull, accountId: item.repo.accountId) ? .mine : .team
        if let repoFilter, repoFilter != item.repo.id { self.repoFilter = nil }
        selectedID = id
        return true
    }

    /// Narrows the inbox to the followed repo `repoKey` (Ruling 7); any other
    /// key changes nothing. The selection stays if it's one of that repo's
    /// pull requests and goes if not.
    func showRepo(_ repoKey: String) {
        guard repos.contains(where: { $0.id == repoKey }) else { return }
        repoFilter = repoKey
        if let selectedID, !selectedID.hasPrefix(repoKey + "#") { self.selectedID = nil }
    }

    /// The rows of every followed repo, in `repos` order.
    private var followedRows: [InboxPull] {
        repos.flatMap { repo in (pulls[repo.id] ?? []).map { InboxPull(repo: repo, pull: $0) } }
    }
}
