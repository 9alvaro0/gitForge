import Foundation

/// "Search all of <host>" and the repos found that way (R3 Rulings 12 and
/// 13): which instances can be searched, with which account and under which
/// owners, and how the inbox shows a browsed repo. What changes the inbox
/// (`searchHost`, `openFoundRepo`, `retryPendingLink`) is in
/// `ReviewsStore.swift`, next to the state it sets.
extension ReviewsStore {
    /// Least characters, without the spaces around them, a search asks for.
    static let searchMinimum = 3
    /// Most owners a search of github.com or gitlab.com keeps to.
    static let searchOwnerLimit = 5

    /// The instances with an account in the inbox, once each, in the order
    /// of the accounts: one "Search all of <host>" row each.
    var searchInstances: [HostingInstance] {
        var seen: Set<UUID> = []
        return inboxAccounts.compactMap { seen.insert($0.instance.id).inserted ? $0.instance : nil }
    }

    /// The keys (`FollowedRepos.key`) of the repos followed: a found repo
    /// among them is marked "Followed".
    var followedKeys: Set<String> { Set(repos.map(\.id)) }

    /// The account a search of instance `instanceId` runs with, and whose
    /// presence lets a pending link be opened again: its first that signs,
    /// in the order of the accounts.
    func searchAccount(on instanceId: UUID) -> HostingAccount? {
        inboxAccounts.first { $0.instance.id == instanceId && AccountGitCredentials.signs($0.account) }?.account
    }

    /// The owners a search of `instance` keeps to (Ruling 12): `nil` on an
    /// instance of the user's own, which searches all the account sees. On
    /// github.com and gitlab.com, the first path segment of the account's
    /// repos (`members`), those with most repos first, by name when tied, at
    /// most `searchOwnerLimit`, once each whatever their case. On GitLab the
    /// account's `login` is left out: a personal namespace isn't a group.
    static func searchOwners(on instance: HostingInstance, members: [RemoteRepoSummary], login: String?) -> [String]? {
        guard instance.isBuiltIn else { return nil }
        var owners: [String: (name: String, repos: Int)] = [:]
        for member in members {
            guard let owner = member.fullName.split(separator: "/").first.map(String.init), !owner.isEmpty else {
                continue
            }
            owners[owner.lowercased(), default: (owner, 0)].repos += 1
        }
        if instance.kind == .gitlab, let login { owners[login.lowercased()] = nil }
        let ranked = owners.values.sorted { lhs, rhs in
            guard lhs.repos == rhs.repos else { return lhs.repos > rhs.repos }
            return lhs.name.lowercased() < rhs.name.lowercased()
        }
        return ranked.prefix(searchOwnerLimit).map(\.name)
    }

    /// The pull requests and the repos matching `text`, both asked at once;
    /// either one's error is the search's.
    nonisolated static func searchPullsAndRepos(_ text: String, owners: [String]?, on instance: HostingInstance,
                                                token: String,
                                                with search: any HostSearching) async throws -> HostSearchResults {
        async let pulls = search.searchPulls(text, owners: owners, on: instance, token: token)
        async let repos = search.searchRepos(text, owners: owners, on: instance, token: token)
        return try await HostSearchResults(pulls: pulls, repos: repos)
    }

    /// The browsed repo `repoFilter` names, if it names one.
    var filteredBrowsedRepo: ReviewRepo? {
        guard let repoFilter else { return nil }
        return browsedRepos.first { $0.id == repoFilter }
    }

    /// What the inbox shows narrowed to the browsed `repo` (Ruling 13): one
    /// group with its Others and, when it's the repository open in gitForge
    /// without being followed, its rows, which `openFoundRepo` doesn't make
    /// Others (U1 Ruling C); both halves, newest first, each pull request
    /// once; none without them.
    func browsedGroups(_ repo: ReviewRepo) -> [ReviewGroup] {
        let visiting = visitingRows(of: repo.id)
        let numbers = Set(visiting.map(\.pull.number))
        let opened = others.filter { $0.repo.id == repo.id && !numbers.contains($0.pull.number) }
        let rows = (visiting + opened).sorted { Self.newerFirst($0.pull, $1.pull) }
        return rows.isEmpty ? [] : [ReviewGroup(repo: repo, pulls: rows, error: nil)]
    }
}
