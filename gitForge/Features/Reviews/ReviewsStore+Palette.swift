import Foundation

/// What ⌘K reads from the inbox (R2 Rulings 6, 7 and 9): the pull requests
/// to search, the followed repos that aren't cloned, the repo the inbox is
/// narrowed to and the Others shown. What it does to the inbox, `reveal` and
/// `showRepo`, is in `ReviewsStore.swift`, next to the filter they set.
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
}
