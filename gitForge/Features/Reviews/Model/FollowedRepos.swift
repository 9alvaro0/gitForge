import Foundation

/// Where a followed repo came from: a clone on this Mac, the user's recent
/// activity on the hosting platform, a pattern the user accepted, or a repo the
/// user followed by hand.
nonisolated enum FollowSource: String, Codable, Hashable, Sendable {
    case local
    case activity
    case pattern
    case manual
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
    /// Where the clone's `origin` still points when the repo was renamed or
    /// moved (`host` is its current path); `nil` when `origin` is up to date.
    /// Optional with a `nil` default so a snapshot saved before this existed
    /// still decodes.
    var outdatedOrigin: RemoteHost? = nil

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
    /// The account that would read this clone if it signed: it needs attention
    /// (an expired token, say), so it isn't in `assignedAccountId` nor among the
    /// accounts that sign. `FollowedRepos.merge` keeps the clone with it while
    /// the membership would leave the clone out; `nil` when there is none.
    var waitingAccountId: UUID? = nil
    /// Set when the repo was renamed or moved: `host` is its current path and
    /// this is the old one the clone's `origin` still has.
    var outdatedOrigin: RemoteHost? = nil
}

/// A repo the user was recently active in, as one account saw it.
nonisolated struct ActivityCandidate: Equatable, Sendable {
    let host: RemoteHost
    let accountId: UUID
    let at: Date
    /// The API's HTTPS clone URL.
    let cloneURL: String
}

/// A repo the user chose rather than a clone or their activity put in the
/// inbox: one a pattern matches (`.pattern`) or one followed by hand
/// (`.manual`). The store resolves the account and the clone URL.
nonisolated struct ChosenCandidate: Equatable, Sendable {
    let host: RemoteHost
    /// The account that reads it: the first of its instance's whose membership
    /// lists the repo, else the first in preference.
    let accountId: UUID
    /// `.pattern` or `.manual`; `FollowedRepos.merge` ignores any other.
    let source: FollowSource
    /// The membership's HTTPS clone URL, else `FollowedRepos.cloneURL(for:)`.
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

    /// Joins the local clones, the API activity and the repos the user chose
    /// into one list of repos.
    ///
    /// - `accounts` are the ones the inbox reads with
    ///   (`ReviewsEnvironment.accounts`), in the order it prefers them: those
    ///   that sign first, each group in the order of `AccountStore.accounts`.
    /// - A repo that comes more than one way keeps the local's host; its clone
    ///   URL is the activity's, else the chosen candidate's.
    /// - A clone keeps the account it comes with (`LocalRemote.assignedAccountId`).
    ///   Without one it takes the best of the accounts whose activity reached
    ///   it, else of its instance's (Ruling 4: the owner's login, else the first).
    /// - `chosen` are the repos a pattern or the user picked (R3 Ruling 4). They
    ///   add their source and never a `lastActivity`. A repo only they reach
    ///   takes the account of the first candidate for it; one that also comes
    ///   as a clone or by activity follows the rules above.
    /// - A local repo with no account of the inbox on its instance is left out.
    /// - `memberKeys` holds, for each instance whose membership is known, the
    ///   `key`s of the repos its accounts belong to. On such an instance a
    ///   clone counts only if its key is among them, or if the activity or a
    ///   chosen candidate reached it too (`vouchedKeys`): activity is matched
    ///   against the same membership, so it is a member as a rule, but
    ///   activity carried over from an earlier round isn't checked again. An
    ///   instance with no entry is unknown, and its clones count. The default,
    ///   none known, is every clone counting.
    /// - A clone the membership would leave out stays when it has a
    ///   `LocalRemote.waitingAccountId` that is one of the inbox's accounts on
    ///   its instance (R3 Ruling 11): it keeps that account, like an assigned
    ///   one. On a clone that passes the membership check it is ignored.
    /// - `hidden` holds the `key`s of the repos the user hid. They're removed
    ///   before ordering and cutting, so they don't count in `dropped` either.
    /// - The result is ordered by `lastActivity` (newest first, then by key)
    ///   and cut to `limit`.
    static func merge(local: [LocalRemote], activity: [ActivityCandidate], chosen: [ChosenCandidate] = [],
                      hidden: Set<String> = [], accounts: [HostingAccount], instances: [HostingInstance],
                      memberKeys: [UUID: Set<String>] = [:]) -> FollowedSet {
        var drafts: [String: Draft] = [:]
        let eligible = chosen.filter { isEligible($0, accounts: accounts, instances: instances) }
        let vouched = vouchedKeys(activity: activity, chosen: chosen, accounts: accounts, instances: instances)

        for remote in local {
            guard let instance = instance(for: remote.host, in: instances) else { continue }
            let repoKey = key(remote.host)
            let usable = accounts.filter { $0.instanceId == instance.id }
            var assigned = remote.assignedAccountId.flatMap { id in usable.first { $0.id == id } }
            if let members = memberKeys[instance.id], !members.contains(repoKey), !vouched.contains(repoKey) {
                // The membership leaves it out: only the account it waits for keeps it.
                let waiting = remote.waitingAccountId.flatMap { id in usable.first { $0.id == id } }
                guard let waiting else { continue }
                assigned = waiting
            }
            guard let account = assigned ?? preferredAccount(for: remote.host, among: usable) else { continue }

            let opened = remote.repository.lastOpenedAt
            if var draft = drafts[repoKey] {
                draft.lastActivity = max(draft.lastActivity ?? opened, opened)
                drafts[repoKey] = draft
            } else {
                drafts[repoKey] = Draft(host: remote.host, localAccountId: account.id, localAccountAssigned: assigned != nil,
                                        sources: [.local], lastActivity: opened, localURL: remote.repository.url,
                                        outdatedOrigin: remote.outdatedOrigin)
            }
        }

        for candidate in activity {
            guard let account = usableAccount(candidate.accountId, for: candidate.host,
                                              in: accounts, instances: instances) else { continue }

            let repoKey = key(candidate.host)
            var draft = drafts[repoKey] ?? Draft(host: candidate.host)
            draft.sources.insert(.activity)
            draft.lastActivity = max(draft.lastActivity ?? candidate.at, candidate.at)
            draft.apiCloneURL = draft.apiCloneURL ?? candidate.cloneURL
            draft.seenBy.insert(account.id)
            drafts[repoKey] = draft
        }

        for candidate in eligible {
            let repoKey = key(candidate.host)
            var draft = drafts[repoKey] ?? Draft(host: candidate.host)
            draft.sources.insert(candidate.source)
            draft.chosenCloneURL = draft.chosenCloneURL ?? candidate.cloneURL
            draft.chosenAccountId = draft.chosenAccountId ?? candidate.accountId
            drafts[repoKey] = draft
        }

        let repos = drafts
            .filter { !hidden.contains($0.key) }
            .values
            .compactMap { $0.repo(accounts: accounts) }
            .sorted { lhs, rhs in
                let left = lhs.lastActivity ?? .distantPast
                let right = rhs.lastActivity ?? .distantPast
                return left == right ? lhs.id < rhs.id : left > right
            }
        return FollowedSet(repos: Array(repos.prefix(limit)), dropped: max(0, repos.count - limit))
    }

    /// The `key`s that keep a clone whatever the membership says: those an
    /// activity candidate or a chosen candidate reaches with one of
    /// `accounts` on the repo's instance. `merge` uses it, and the refresh
    /// too, to leave these clones out of the rename lookups (R3 Ruling 10):
    /// a clone kept under its own path mustn't also be followed under the
    /// new one.
    static func vouchedKeys(activity: [ActivityCandidate], chosen: [ChosenCandidate], accounts: [HostingAccount],
                            instances: [HostingInstance]) -> Set<String> {
        let byActivity = activity.filter { candidate in
            usableAccount(candidate.accountId, for: candidate.host, in: accounts, instances: instances) != nil
        }.map { key($0.host) }
        let byChoice = chosen.filter { isEligible($0, accounts: accounts, instances: instances) }.map { key($0.host) }
        return Set(byActivity + byChoice)
    }

    /// A repo's HTTPS clone URL when no membership gives one (Ruling 12).
    static func cloneURL(for host: RemoteHost) -> String {
        "https://\(host.host)/\(host.owner)/\(host.repo).git"
    }

    /// `accounts` in the order they're tried for `host` (Ruling 4, and R2
    /// Ruling 10 for a link): the one whose login is the repo's owner first,
    /// the rest in the order given.
    static func accountsInPreference(for host: RemoteHost, among accounts: [HostingAccount]) -> [HostingAccount] {
        let owner = host.owner.lowercased()
        guard let index = accounts.firstIndex(where: { $0.login?.lowercased() == owner }) else { return accounts }
        var rest = accounts
        return [rest.remove(at: index)] + rest
    }

    // MARK: - Private

    /// A repo being assembled. `host` is the local remote's when there is one,
    /// else the first activity candidate's, else the first chosen one's.
    private struct Draft {
        var host: RemoteHost
        /// The account a clone resolved to (Ruling 4); `nil` for repos with no clone.
        var localAccountId: UUID?
        /// The clone came with its account (`LocalRemote.assignedAccountId`):
        /// the activity doesn't change it.
        var localAccountAssigned = false
        var sources: Set<FollowSource> = []
        var lastActivity: Date?
        var apiCloneURL: String?
        var localURL: URL?
        /// Where the first clone's `origin` still points, if it was renamed.
        var outdatedOrigin: RemoteHost?
        /// Accounts whose activity reached this repo.
        var seenBy: Set<UUID> = []
        /// The account and clone URL of the first chosen candidate for this repo.
        var chosenAccountId: UUID?
        var chosenCloneURL: String?

        /// A clone that came with its account keeps it. Otherwise the repo
        /// takes the best of the accounts that saw it (owner's login, else the
        /// first in `accounts` order), a clone no activity reached keeps the
        /// one it resolved to, and a repo only chosen candidates reached takes
        /// the first candidate's. `nil` only if none is left.
        func repo(accounts: [HostingAccount]) -> ReviewRepo? {
            let seen = FollowedRepos.preferredAccount(for: host, among: accounts.filter { seenBy.contains($0.id) })?.id
            let accountId = localAccountAssigned ? localAccountId : seen ?? localAccountId ?? chosenAccountId
            guard let accountId else { return nil }
            return ReviewRepo(host: host, accountId: accountId, sources: sources, lastActivity: lastActivity,
                              cloneURL: apiCloneURL ?? chosenCloneURL ?? FollowedRepos.cloneURL(for: host),
                              localURL: localURL, outdatedOrigin: outdatedOrigin)
        }
    }

    /// The account of the inbox with this id, if it is one of `host`'s
    /// instance's.
    private static func usableAccount(_ accountId: UUID, for host: RemoteHost, in accounts: [HostingAccount],
                                      instances: [HostingInstance]) -> HostingAccount? {
        guard let instance = instance(for: host, in: instances) else { return nil }
        return accounts.first { $0.id == accountId && $0.instanceId == instance.id }
    }

    /// A chosen candidate `merge` takes: a pattern's or a manual one, with an
    /// account of the inbox on its instance.
    private static func isEligible(_ candidate: ChosenCandidate, accounts: [HostingAccount],
                                   instances: [HostingInstance]) -> Bool {
        (candidate.source == .pattern || candidate.source == .manual)
            && usableAccount(candidate.accountId, for: candidate.host, in: accounts, instances: instances) != nil
    }

    /// The declared instance a repo lives on.
    private static func instance(for host: RemoteHost, in instances: [HostingInstance]) -> HostingInstance? {
        instances.first { $0.host == host.host }
    }

    /// Ruling 4 without an assignment: the account whose login is the repo's
    /// owner, else the first one.
    private static func preferredAccount(for host: RemoteHost, among accounts: [HostingAccount]) -> HostingAccount? {
        accountsInPreference(for: host, among: accounts).first
    }
}
