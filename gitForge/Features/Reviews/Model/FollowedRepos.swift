import Foundation

/// Where a followed repo came from: a clone on this Mac or the user's recent
/// activity on the hosting platform.
nonisolated enum FollowSource: String, Codable, Hashable, Sendable {
    case local
    case activity
}

/// A repository whose pull requests the Reviews inbox loads, and the account
/// that loads them.
nonisolated struct ReviewRepo: Codable, Equatable, Identifiable, Sendable {
    let host: RemoteHost
    let accountId: UUID
    var sources: Set<FollowSource>
    /// The latest of the clone's `lastOpenedAt` and the user's last activity.
    var lastActivity: Date?
    var cloneURL: String
    /// The clone on this Mac, if any.
    var localURL: URL?

    var id: String { FollowedRepos.key(host) }
}

/// A clone on this Mac whose `origin` is a declared instance.
nonisolated struct LocalRemote: Equatable, Sendable {
    let host: RemoteHost
    let repository: Repository
    /// The account the clone's own Pull requests screen reads it with: the
    /// user's choice, or the automatic rules' pick among the accounts that
    /// sign. `nil` when none fits or several do and nothing tells them apart.
    let assignedAccountId: UUID?
}

/// A repo the user was recently active in, as one account saw it.
nonisolated struct ActivityCandidate: Equatable, Sendable {
    let host: RemoteHost
    let accountId: UUID
    let at: Date
    /// The API's HTTPS clone URL.
    let cloneURL: String
}

/// What `FollowedRepos.merge` returns: the repos to load (at most
/// `FollowedRepos.limit`) and how many were left out.
nonisolated struct FollowedSet: Equatable, Sendable {
    var repos: [ReviewRepo]
    var dropped: Int
}

/// Decides which repositories the Reviews inbox follows (R1 Rulings 1, 4, 5, 12).
nonisolated enum FollowedRepos {
    /// Most repos the inbox loads; the rest are counted in `FollowedSet.dropped`.
    static let limit = 100
    /// How far back the activity queries look.
    static let activityWindow: TimeInterval = 90 * 24 * 3600

    /// Two paths that differ only in case are the same repo.
    static func key(_ host: RemoteHost) -> String {
        "\(host.host)/\(host.owner)/\(host.repo)".lowercased()
    }

    /// Joins the local clones and the API activity into one list of repos.
    ///
    /// - `accounts` are the ones the inbox reads with
    ///   (`ReviewsEnvironment.accounts`), in the order it prefers them: those
    ///   that sign first, each group in the order of `AccountStore.accounts`.
    /// - A repo that comes both ways keeps the local's host; its clone URL is
    ///   the API's.
    /// - A clone keeps the account it comes with (`LocalRemote.assignedAccountId`).
    ///   Without one it takes the best of the accounts whose activity reached
    ///   it, else of its instance's (Ruling 4: the owner's login, else the first).
    /// - A local repo with no account of the inbox on its instance is left out.
    /// - `memberKeys` holds, for each instance whose membership is known, the
    ///   `key`s of the repos its accounts belong to. On such an instance a
    ///   clone counts only if its key is among them, or if the activity
    ///   reached it too (which makes it a member by construction). An
    ///   instance with no entry is unknown, and its clones count. The
    ///   default, none known, is every clone counting.
    /// - The result is ordered by `lastActivity` (newest first, then by key)
    ///   and cut to `limit`.
    static func merge(local: [LocalRemote], activity: [ActivityCandidate],
                      accounts: [HostingAccount], instances: [HostingInstance],
                      memberKeys: [UUID: Set<String>] = [:]) -> FollowedSet {
        var drafts: [String: Draft] = [:]
        let activityKeys = Set(activity.compactMap { candidate in
            accountSeeing(candidate, in: accounts, instances: instances) == nil ? nil : key(candidate.host)
        })

        for remote in local {
            guard let instance = instance(for: remote.host, in: instances) else { continue }
            let repoKey = key(remote.host)
            if let members = memberKeys[instance.id], !members.contains(repoKey), !activityKeys.contains(repoKey) {
                continue
            }
            let usable = accounts.filter { $0.instanceId == instance.id }
            let assigned = remote.assignedAccountId.flatMap { id in usable.first { $0.id == id } }
            guard let account = assigned ?? preferredAccount(for: remote.host, among: usable) else { continue }

            let opened = remote.repository.lastOpenedAt
            if var draft = drafts[repoKey] {
                draft.lastActivity = max(draft.lastActivity ?? opened, opened)
                drafts[repoKey] = draft
            } else {
                drafts[repoKey] = Draft(host: remote.host, localAccountId: account.id, localAccountAssigned: assigned != nil,
                                        sources: [.local], lastActivity: opened, localURL: remote.repository.url)
            }
        }

        for candidate in activity {
            guard let account = accountSeeing(candidate, in: accounts, instances: instances) else { continue }

            let repoKey = key(candidate.host)
            var draft = drafts[repoKey] ?? Draft(host: candidate.host)
            draft.sources.insert(.activity)
            draft.lastActivity = max(draft.lastActivity ?? candidate.at, candidate.at)
            draft.apiCloneURL = draft.apiCloneURL ?? candidate.cloneURL
            draft.seenBy.insert(account.id)
            drafts[repoKey] = draft
        }

        let repos = drafts.values
            .compactMap { $0.repo(accounts: accounts) }
            .sorted { lhs, rhs in
                let left = lhs.lastActivity ?? .distantPast
                let right = rhs.lastActivity ?? .distantPast
                return left == right ? lhs.id < rhs.id : left > right
            }
        return FollowedSet(repos: Array(repos.prefix(limit)), dropped: max(0, repos.count - limit))
    }

    // MARK: - Private

    /// A repo being assembled. `host` is the local remote's when there is one,
    /// else the first activity candidate's.
    private struct Draft {
        var host: RemoteHost
        /// The account a clone resolved to (Ruling 4); `nil` for activity-only repos.
        var localAccountId: UUID?
        /// The clone came with its account (`LocalRemote.assignedAccountId`):
        /// the activity doesn't change it.
        var localAccountAssigned = false
        var sources: Set<FollowSource> = []
        var lastActivity: Date?
        var apiCloneURL: String?
        var localURL: URL?
        /// Accounts whose activity reached this repo.
        var seenBy: Set<UUID> = []

        /// A clone that came with its account keeps it. Otherwise the repo
        /// takes the best of the accounts that saw it (owner's login, else the
        /// first in `accounts` order), and a clone no activity reached keeps
        /// the one it resolved to. `nil` only if none is left.
        func repo(accounts: [HostingAccount]) -> ReviewRepo? {
            let seen = FollowedRepos.preferredAccount(for: host, among: accounts.filter { seenBy.contains($0.id) })?.id
            let accountId = localAccountAssigned ? localAccountId : seen ?? localAccountId
            guard let accountId else { return nil }
            return ReviewRepo(host: host, accountId: accountId, sources: sources, lastActivity: lastActivity,
                              cloneURL: apiCloneURL ?? "https://\(host.host)/\(host.owner)/\(host.repo).git",
                              localURL: localURL)
        }
    }

    /// The account of the inbox that saw `candidate`, if it is one of its
    /// instance's.
    private static func accountSeeing(_ candidate: ActivityCandidate, in accounts: [HostingAccount],
                                      instances: [HostingInstance]) -> HostingAccount? {
        guard let instance = instance(for: candidate.host, in: instances) else { return nil }
        return accounts.first { $0.id == candidate.accountId && $0.instanceId == instance.id }
    }

    /// The declared instance a repo lives on.
    private static func instance(for host: RemoteHost, in instances: [HostingInstance]) -> HostingInstance? {
        instances.first { $0.host == host.host }
    }

    /// Ruling 4 without an assignment: the account whose login is the repo's
    /// owner, else the first one.
    private static func preferredAccount(for host: RemoteHost, among accounts: [HostingAccount]) -> HostingAccount? {
        let owner = host.owner.lowercased()
        return accounts.first { $0.login?.lowercased() == owner } ?? accounts.first
    }
}
