import Foundation

/// The repository open in gitForge, as Team and Mine see it (pulls-unified §4.2).
@MainActor
struct ActiveRepositoryPulls {
    /// The clone on this Mac.
    let localURL: URL
    /// Its own pull requests store: it knows the repository's host, holds its
    /// open pull requests and opens their detail with the local actions.
    let store: PullRequestStore
}

/// The repository open in gitForge, in the inbox (U1 Rulings 3 and 4). A
/// followed repo only goes first. One that isn't followed (`visitingRepo`) is
/// a group of its own, first too, with the open pull requests its store
/// already holds: nothing is read for it, it isn't counted for the sidebar
/// and it isn't added to the repos followed. Its store, not the inbox's, opens
/// the detail of its pull requests (`ReviewsStore.detailStore(for:)`).
extension ReviewsStore {
    /// The key (`FollowedRepos.key`) of the repository open in gitForge: that
    /// of the followed repo it is (`followedRepo(for:)`), else of the host its
    /// store knows. A repository with no remote, or on an instance that isn't
    /// declared, and that no followed repo is cloned at, has none: the inbox
    /// then has no open repository.
    var activeRepoKey: String? {
        guard let active = activeRepository else { return nil }
        return followedRepo(for: active)?.id ?? active.store.host.map(FollowedRepos.key)
    }

    /// Whether `repo` is the repository open in gitForge.
    func isActive(_ repo: ReviewRepo) -> Bool {
        repo.id == activeRepoKey
    }

    /// The open repository when the inbox doesn't follow it: a repo "of
    /// passage", with no sources, the clone it was opened from and the first
    /// account of its instance. `nil` when it's followed, hidden in Settings
    /// (hiding wins), or no account is on its instance.
    var visitingRepo: ReviewRepo? { visiting?.repo }

    /// The pull requests the list and ⌘K offer: those of every followed repo
    /// and those of the visiting repo.
    var inboxRows: [InboxPull] { followedRows + visitingRows }

    /// What the detail offers for `item`'s local work (spec §4.3): the open
    /// repository's own actions, else to open its clone or to clone it.
    func detailAction(for item: InboxPull) -> PullsDetailAction {
        isActive(item.repo) ? .local : .repo(ReviewRepoAction(item.repo))
    }

    /// Whether `item` is the user's. A followed repo's rows go by the login of
    /// its account; the visiting repo's, by the user of its own store, and
    /// with that still unread none is the user's (as in R1 Ruling 7).
    func isMine(_ item: InboxPull) -> Bool {
        guard let visiting, visiting.repo.id == item.repo.id else {
            return isMine(item.pull, accountId: item.repo.accountId)
        }
        return Self.isAuthor(item.pull, login: visiting.store.currentUser)
    }

    /// The visiting repo's rows when `repoKey` is the visiting repo; none
    /// otherwise.
    func visitingRows(of repoKey: String) -> [InboxPull] {
        guard let visiting, visiting.repo.id == repoKey else { return [] }
        return visitingRows
    }

    /// Whether pull request `number` is a row of the visiting repo `repoKey`.
    func isVisitingRow(repoKey: String, number: Int) -> Bool {
        guard repoKey == activeRepoKey, let visiting else { return false }
        return visiting.store.items.contains { $0.number == number }
    }

    /// `groups`, the ones `half` lists, with the open repository's first. A
    /// followed one is moved up; the visiting one, if it has rows in `half`,
    /// is put in front. Not when the inbox is `narrowed` to a repo, which
    /// shows just that one.
    func placingActiveFirst(_ groups: [ReviewGroup], of half: ReviewsFilter, narrowed: Bool) -> [ReviewGroup] {
        if !narrowed, let group = visitingGroup(of: half) { return [group] + groups }
        guard let key = activeRepoKey, let index = groups.firstIndex(where: { $0.id == key }), index > 0 else {
            return groups
        }
        var ordered = groups
        ordered.insert(ordered.remove(at: index), at: 0)
        return ordered
    }

    // MARK: Private

    /// The followed repo that `active` is (U1 Ruling G): the one whose clone is
    /// its folder, else the one at the path of its store's host. The folder
    /// goes first because a followed clone whose repo was renamed is followed
    /// under its new path, while its `origin`, and so the store's host, keeps
    /// the old one (`outdatedOrigin`, R3 Ruling 10).
    private func followedRepo(for active: ActiveRepositoryPulls) -> ReviewRepo? {
        let folder = active.localURL.standardizedFileURL.path
        if let cloned = repos.first(where: { $0.localURL?.standardizedFileURL.path == folder }) { return cloned }
        guard let host = active.store.host else { return nil }
        let key = FollowedRepos.key(host)
        return repos.first { $0.id == key }
    }

    /// The visiting repo and the store its rows come from.
    private var visiting: (repo: ReviewRepo, store: PullRequestStore)? {
        guard let active = activeRepository, let host = active.store.host, followedRepo(for: active) == nil else {
            return nil
        }
        let key = FollowedRepos.key(host)
        guard !config.hidden.contains(where: { FollowedRepos.key($0) == key }),
              let account = inboxAccounts.first(where: { $0.instance.host == host.host })?.account else { return nil }
        let repo = ReviewRepo(host: host, accountId: account.id, sources: [], lastActivity: nil,
                              cloneURL: FollowedRepos.cloneURL(for: host), localURL: active.localURL)
        return (repo, active.store)
    }

    /// The visiting repo's open pull requests, as its store has them.
    private var visitingRows: [InboxPull] {
        guard let visiting else { return [] }
        return visiting.store.items.map { InboxPull(repo: visiting.repo, pull: $0) }
    }

    /// The visiting repo's group for `half`, newest first; `nil` with no rows
    /// in it.
    private func visitingGroup(of half: ReviewsFilter) -> ReviewGroup? {
        guard let visiting else { return nil }
        let rows = visitingRows
            .filter { Self.isAuthor($0.pull, login: visiting.store.currentUser) == (half == .mine) }
            .sorted { Self.newerFirst($0.pull, $1.pull) }
        return rows.isEmpty ? nil : ReviewGroup(repo: visiting.repo, pulls: rows, error: nil)
    }

    private static func isAuthor(_ pull: PullRequest, login: String?) -> Bool {
        guard let login, let author = pull.authorLogin else { return false }
        return author.lowercased() == login.lowercased()
    }
}
