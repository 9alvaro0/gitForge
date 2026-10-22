import Foundation

/// What ⌘K reads from the inbox and what it does to it (R2 Rulings 6 to 9):
/// the pull requests to search, the followed repos that aren't cloned, the
/// filter by repo, picking a row from outside the list and the Others shown.
extension ReviewsStore {
    /// The repo `repoFilter` names, while it's still followed.
    var filteredRepo: ReviewRepo? {
        guard let repoFilter else { return nil }
        return repos.first { $0.id == repoFilter }
    }

    /// What the palette searches (Rulings 5 and 9): the Others that aren't
    /// rows of the followed list, in their order, then every open pull
    /// request of the followed repos, newest first: both halves, drafts
    /// included, whatever the filters show. The Others go first: the user
    /// opened them this session, and ⌘K keeps only the first pull requests.
    var searchablePulls: [InboxPull] {
        others.filter { !isListed(repoKey: $0.repo.id, number: $0.pull.number) }
            + followedRows.sorted { Self.newerFirst($0.pull, $1.pull) }
    }

    /// The Others the list shows (Ruling 9): those that aren't rows of the
    /// followed list, and the selected one while Team or Mine hides its row,
    /// so the selection doesn't vanish. Team and Mine don't filter them;
    /// with `repoFilter`, none shows.
    var visibleOthers: [InboxPull] {
        guard repoFilter == nil else { return [] }
        return others.filter { item in
            guard isListed(repoKey: item.repo.id, number: item.pull.number) else { return true }
            return item.id == selectedID && !groups.contains { $0.pulls.contains { $0.id == item.id } }
        }
    }

    /// Whether pull request `number` is a row of the followed repo `repoKey`.
    func isListed(repoKey: String, number: Int) -> Bool {
        pulls[repoKey]?.contains { $0.number == number } == true
    }

    /// The followed repos with no clone on this Mac, in `repos` order
    /// (Ruling 6).
    var unclonedRepos: [ReviewRepo] {
        repos.filter { $0.localURL == nil }
    }

    /// Selects `id` from outside the list (Ruling 8). For a row of a
    /// followed repo, the inbox moves to the half that shows it, Mine if it's
    /// the user's and Team if not, and drops the filter by a repo other than
    /// its own; for an Other, it drops the filter by repo, which hides the
    /// Others. `false`, with nothing changed, when `id` is neither.
    @discardableResult
    func reveal(_ id: InboxPull.ID) -> Bool {
        if let item = followedRows.first(where: { $0.id == id }) {
            filter = isMine(item.pull, accountId: item.repo.accountId) ? .mine : .team
            if let repoFilter, repoFilter != item.repo.id { self.repoFilter = nil }
        } else if others.contains(where: { $0.id == id }) {
            repoFilter = nil
        } else {
            return false
        }
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
