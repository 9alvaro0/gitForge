import Foundation
import Observation

// MARK: - Environment

/// What `ReviewsStore` reads the world through: the account store, the
/// catalog and the real API clients in the app; fakes in tests.
struct ReviewsEnvironment {
    /// The accounts that sign (`AccountGitCredentials.signs`) and those that
    /// need attention, with their instance, in `AccountStore.accounts` order.
    /// One that needs attention answers `.connectAccount` from `token`: it
    /// stays in `accountsNeedingAttention` and its repos keep their pull
    /// requests until it's connected again. The store puts the accounts that
    /// sign first, so a dead one never wins a repo as an instance's first
    /// account (Ruling 4.3); the owner's login or its own activity still can
    /// give it one.
    var accounts: @MainActor () -> [(account: HostingAccount, instance: HostingInstance)]
    /// The catalog's clones whose `origin` is on a declared instance, each
    /// with the account its own Pull requests screen reads it with, when one
    /// stands out (`LocalRemote.assignedAccountId`); nobody is asked. Which of
    /// them the inbox follows is not decided here: `FollowedRepos.merge` keeps
    /// a clone only if an account of its instance belongs to the repo, when
    /// the memberships tell. A refresh cancelled while this runs commits
    /// nothing: `GitCLI` reads the remotes with `try?`, so a cancelled read
    /// comes back empty.
    var localRemotes: @MainActor () async -> [LocalRemote]
    /// An account's token; `rejected` is one that just got a 401.
    var token: @MainActor (_ accountId: UUID, _ rejected: String?) async -> PullRequestAuthResult
    var makeProvider: @MainActor (RemoteHost) -> PullRequestProvider
    var makeBrowser: @MainActor (HostingInstance.Kind) -> any RemoteRepoBrowsing
    var makeActivity: @MainActor (HostingInstance.Kind) -> any ReviewActivitySource
    var snapshots: ReviewsSnapshotStore
    var now: @MainActor () -> Date = { .now }
    /// The writes of the detail stores: reviews, threads, merge.
    var makeReviewProvider: @MainActor (RemoteHost) -> PullRequestReviewProvider = {
        PullRequestReviewProviderFactory.make(for: $0)
    }
}

// MARK: - Store

/// The Reviews inbox: works out the repos the user follows, reads their open
/// pull requests a few at a time, keeps the last read on disk and gives the
/// sidebar its count. Each repo's pull requests open in a `PullRequestStore`
/// of its own (`detailStore(for:)`). The refresh pipeline's helpers are in
/// `ReviewsStore+Refresh.swift`.
@Observable
@MainActor
final class ReviewsStore {
    /// Least time between two refreshes that aren't forced.
    static let reloadThrottle: TimeInterval = 30
    /// How often the inbox refreshes on its own while the app is online and active.
    static let autoRefreshInterval: Duration = .seconds(300)
    /// Most pull request lists read at once.
    static let concurrency = 6
    /// How long an account's membership is used before it's read again.
    static let membershipTTL: TimeInterval = 24 * 3600
    /// Most pages of membership read per account (Ruling 3).
    static let membershipPages = 10

    /// The repos followed, most recent activity first.
    private(set) var repos: [ReviewRepo] = []
    /// Open pull requests by `ReviewRepo.id`.
    private(set) var pulls: [String: [PullRequest]] = [:]
    /// The user's login on each account, by account id.
    private(set) var logins: [UUID: String] = [:]
    /// Why a repo's pull requests couldn't be read, by `ReviewRepo.id`.
    private(set) var repoErrors: [String: String] = [:]
    /// Accounts to connect again: their token was rejected and couldn't be renewed.
    private(set) var accountsNeedingAttention: Set<UUID> = []
    /// Repos left out by `FollowedRepos.limit`.
    private(set) var droppedByLimit = 0
    private(set) var isRefreshing = false
    /// When the pull requests were last read; at launch, the snapshot's date.
    private(set) var lastRefreshedAt: Date?
    /// The last refresh reached no repo, for lack of network.
    private(set) var lastRefreshFailed = false
    var filter: ReviewsFilter = .team
    /// The repo the inbox is narrowed to (`ReviewRepo.id`), with the pull
    /// requests of both halves; `nil` shows every repo, by `filter` (R2
    /// Ruling 7). `showRepo(_:)` sets it; `showAllRepos()`, `reveal(_:)` and
    /// a refresh that stops following the repo clear it.
    private(set) var repoFilter: String?
    var selectedID: InboxPull.ID?
    /// Pull requests opened from a link that weren't rows of the followed
    /// list when they landed, by opening order, the last one first (R2
    /// Ruling 9). Only for the session: they never reach the snapshot.
    private(set) var others: [InboxPull] = []
    /// The link `openLink` is reading, while it does (R2 Ruling 11).
    private(set) var openingLink: PendingLink?

    private let environment: ReviewsEnvironment
    @ObservationIgnored private var memberships: [UUID: MembershipCache] = [:]
    @ObservationIgnored private var detailStores: [String: PullRequestStore] = [:]
    /// When the last refresh started, for the throttle.
    @ObservationIgnored private var lastRoundAt: Date?
    /// Accounts whose login was read this session (Ruling 11).
    @ObservationIgnored private var loginLookups: Set<UUID> = []
    /// The newest read started for each repo: an older one that lands later
    /// (a refresh overlapping a `reload`, a repo that left) is dropped.
    @ObservationIgnored private var latestRead: [String: UInt64] = [:]
    @ObservationIgnored private var readCounter: UInt64 = 0
    /// Bumped by every `open`: one that waited on its token longer than the
    /// next one doesn't select over it.
    @ObservationIgnored private var openGen: UInt64 = 0
    /// The clones the last refresh saw, by `FollowedRepos.key`: an Other of a
    /// repo that isn't followed goes to its clone, when there's one.
    @ObservationIgnored private var knownClones: [String: URL] = [:]
    /// Bumped by every `openLink`: an earlier one that lands later adds its
    /// row but selects nothing (R2 Ruling 11).
    @ObservationIgnored private var linkGen: UInt64 = 0
    /// The `openLink` that last opened each Other, for their order.
    @ObservationIgnored private var otherGens: [InboxPull.ID: UInt64] = [:]
    @ObservationIgnored private var autoRefreshTask: Task<Void, Never>?

    init(environment: ReviewsEnvironment) {
        self.environment = environment
    }

    // MARK: Reading

    var hasAccounts: Bool { !environment.accounts().isEmpty }

    /// The accounts of `accountsNeedingAttention` that own at least one
    /// followed repo, with their instance, in store order, for the inbox's
    /// "Reconnect" notices. A stale token saved next to working accounts, with
    /// no repo of its own, is still in `accountsNeedingAttention` but says
    /// nothing here: there's nothing in the inbox to reconnect it for. One
    /// whose repos are still listed (activity repos carried over, a clone
    /// assigned to it) keeps its notice (spec §4.2). A clone assigned to it
    /// can leave, though: where the usable accounts of its instance have a
    /// complete membership that doesn't list the repo, it isn't followed, and
    /// the notice goes with the account's last repo. One that was removed
    /// meanwhile is left out.
    var accountsToReconnect: [(account: HostingAccount, instance: HostingInstance)] {
        guard !accountsNeedingAttention.isEmpty else { return [] }
        let owners = Set(repos.map(\.accountId))
        return environment.accounts().filter {
            accountsNeedingAttention.contains($0.account.id) && owners.contains($0.account.id)
        }
    }

    /// The selected row, while the current filter shows it: in its group or
    /// among the Others shown.
    var selectedItem: InboxPull? {
        guard let selectedID else { return nil }
        for group in groups {
            if let item = group.pulls.first(where: { $0.id == selectedID }) { return item }
        }
        return visibleOthers.first { $0.id == selectedID }
    }

    /// Forgets a selection the list no longer shows: it left with a refresh,
    /// or the filter moved it to the other half. The detail then shows
    /// nothing rather than jumping to another pull request.
    func dropHiddenSelection() {
        if selectedID != nil, selectedItem == nil { selectedID = nil }
    }

    /// The current filter's groups, by their newest update, then the repos
    /// that failed with nothing to show (Rulings 8 and 9). With `repoFilter`,
    /// only that repo's, whoever opened the pull requests (R2 Ruling 7).
    var groups: [ReviewGroup] {
        var loaded: [(group: ReviewGroup, newest: Date)] = []
        var failed: [ReviewGroup] = []
        let isOneRepo = repoFilter != nil
        for repo in repos where !isOneRepo || repo.id == repoFilter {
            let rows = (pulls[repo.id] ?? [])
                .filter { isOneRepo || isMine($0, accountId: repo.accountId) == (filter == .mine) }
                .sorted(by: Self.newerFirst)
                .map { InboxPull(repo: repo, pull: $0) }
            if let newest = rows.first {
                loaded.append((ReviewGroup(repo: repo, pulls: rows, error: repoErrors[repo.id]),
                               newest.pull.updatedAt ?? .distantPast))
            } else if let error = repoErrors[repo.id] {
                failed.append(ReviewGroup(repo: repo, pulls: [], error: error))
            }
        }
        let ordered = loaded.sorted { lhs, rhs in
            lhs.newest == rhs.newest ? lhs.group.id < rhs.group.id : lhs.newest > rhs.newest
        }
        return ordered.map(\.group) + failed
    }

    /// The current filter's groups and the Others shown; with neither, the
    /// loading placeholder while a read runs and something is still unknown
    /// (`hasUnreadRepos`), else the empty state. Not only the first read
    /// ever: the first after connecting an account says nothing about its
    /// repos until it lands, though an earlier read left a date. But a
    /// refresh over repos all read before leaves the empty state up: an
    /// empty filter (Mine with nothing of the user's) isn't news, and the
    /// skeleton would flash on every refresh.
    var listContent: ReviewsListContent {
        let groups = groups
        let others = visibleOthers
        if !groups.isEmpty || !others.isEmpty { return .groups(groups, others: others) }
        return isRefreshing && hasUnreadRepos ? .loading : .empty
    }

    /// No repo is followed yet, or one has neither pull requests nor an error
    /// (`pulls` keeps an empty list for a repo read with none open, which is
    /// known). The repos of an account in `accountsNeedingAttention` don't
    /// count: they're withheld, never read until it's connected again. With
    /// `repoFilter`, only that repo counts: another one still unread says
    /// nothing about what the list shows.
    private var hasUnreadRepos: Bool {
        if let filteredRepo { return isUnread(filteredRepo) }
        return repos.isEmpty || repos.contains { isUnread($0) }
    }

    private func isUnread(_ repo: ReviewRepo) -> Bool {
        pulls[repo.id] == nil && repoErrors[repo.id] == nil && !accountsNeedingAttention.contains(repo.accountId)
    }

    /// The open pull requests that aren't the user's: drafts don't count, and
    /// with an unknown login none is the user's (Ruling 7).
    var badgeCount: Int {
        repos.reduce(0) { total, repo in
            total + (pulls[repo.id] ?? []).count(where: { $0.state == .open && !isMine($0, accountId: repo.accountId) })
        }
    }

    private func isMine(_ pull: PullRequest, accountId: UUID) -> Bool {
        guard let login = logins[accountId], let author = pull.authorLogin else { return false }
        return author.lowercased() == login.lowercased()
    }

    // Not private: `ReviewsStore+Palette.swift` reads these two as well.
    static func newerFirst(_ lhs: PullRequest, _ rhs: PullRequest) -> Bool {
        let left = lhs.updatedAt ?? .distantPast
        let right = rhs.updatedAt ?? .distantPast
        return left == right ? lhs.number > rhs.number : left > right
    }

    /// The rows of every followed repo, in `repos` order.
    var followedRows: [InboxPull] {
        repos.flatMap { repo in (pulls[repo.id] ?? []).map { InboxPull(repo: repo, pull: $0) } }
    }

    // MARK: Selection and repo filter

    /// Selects `id` from outside the list (R2 Ruling 8). For a row of a
    /// followed repo, the inbox moves to the half that shows it, Mine if it's
    /// the user's and Team if not, and drops the filter by a repo other than
    /// its own; for an Other, it drops the filter by repo, which hides the
    /// Others. `false`, with nothing changed, when `id` is neither.
    @discardableResult
    func reveal(_ id: InboxPull.ID) -> Bool {
        if let item = followedRows.first(where: { $0.id == id }) {
            filter = half(showing: item)
            if let repoFilter, repoFilter != item.repo.id { self.repoFilter = nil }
        } else if others.contains(where: { $0.id == id }) {
            repoFilter = nil
        } else {
            return false
        }
        selectedID = id
        return true
    }

    /// Narrows the inbox to the followed repo `repoKey` (R2 Ruling 7); any
    /// other key changes nothing. The selection stays if it's one of that
    /// repo's pull requests and goes if not.
    func showRepo(_ repoKey: String) {
        guard repos.contains(where: { $0.id == repoKey }) else { return }
        repoFilter = repoKey
        if let selectedID, !selectedID.hasPrefix(repoKey + "#") { self.selectedID = nil }
    }

    /// Shows every repo again, the × of the filter bar (R2 Ruling 7). The
    /// repo's view showed both halves, so a row picked there stays selected:
    /// the inbox moves to the half that shows it, as `reveal` does.
    func showAllRepos() {
        repoFilter = nil
        if let selectedID, let item = followedRows.first(where: { $0.id == selectedID }) {
            filter = half(showing: item)
        }
    }

    /// Mine for the user's own pull request, Team for anyone else's.
    private func half(showing item: InboxPull) -> ReviewsFilter {
        isMine(item.pull, accountId: item.repo.accountId) ? .mine : .team
    }

    // MARK: Snapshot

    /// The last read, from disk: what the inbox shows before the network answers.
    func loadSnapshot() {
        guard let snapshot = environment.snapshots.load() else { return }
        repos = snapshot.repos
        pulls = snapshot.pulls
        memberships = snapshot.memberships
        logins = snapshot.logins
        lastRefreshedAt = snapshot.savedAt
    }

    /// Writes what's loaded, dated by the last refresh that reached the
    /// hosts. Nothing before one did.
    private func saveSnapshot() {
        guard let lastRefreshedAt else { return }
        environment.snapshots.save(ReviewsSnapshot(version: ReviewsSnapshot.currentVersion, savedAt: lastRefreshedAt,
                                                   repos: repos, pulls: pulls, memberships: memberships,
                                                   logins: logins))
    }

    // MARK: Refresh

    /// Works out the repos followed and reads their open pull requests. Does
    /// nothing while one runs, nor within `reloadThrottle` of the last unless
    /// forced. A cancelled round (Reviews left, the auto refresh stopped)
    /// writes nothing to disk. Without accounts it reads nothing, not even
    /// the clones: it only empties what removed accounts left.
    func refresh(force: Bool = false) async {
        let now = environment.now()
        guard !isRefreshing else { return }
        if !force, let lastRoundAt, now.timeIntervalSince(lastRoundAt) < Self.reloadThrottle { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let previousRound = lastRoundAt
        lastRoundAt = now

        let accounts = environment.accounts()
        // Nothing to read with: what the removed accounts left goes, and the
        // round doesn't count for the throttle, so the first one connected
        // reads at once.
        guard !accounts.isEmpty else {
            lastRoundAt = previousRound
            clearWithoutAccounts()
            return
        }
        let tokens = TokenBook(ask: environment.token)
        var activity: [ActivityCandidate] = []
        // The membership of each account that could be had this round.
        var lists: [UUID: MembershipCache] = [:]
        for (account, instance) in accounts {
            await tokens.prepare(account.id)
            let list = await membership(of: account, on: instance, tokens: tokens, now: now)
            lists[account.id] = list
            activity += await recentActivity(of: account, on: instance, members: list?.repos, tokens: tokens, now: now)
                ?? Self.carriedOver(repos, accountId: account.id)
        }
        let local = await environment.localRemotes()
        // Cancelled, the clones may have come back empty: nothing is
        // committed, and the round doesn't count for the throttle.
        guard !Task.isCancelled else {
            lastRoundAt = previousRound
            return
        }
        knownClones = Dictionary(local.map { (FollowedRepos.key($0.host), $0.repository.url) },
                                 uniquingKeysWith: { first, _ in first })
        adopt(FollowedRepos.merge(local: local, activity: activity,
                                  accounts: Self.signingFirst(accounts.map { $0.account }),
                                  instances: accounts.map { $0.instance },
                                  memberKeys: Self.memberKeys(accounts: accounts, lists: lists)))

        let outcomes = await readPulls(of: repos, tokens: tokens)
        // Cancelled while reading: what landed stays, nothing else follows.
        guard !Task.isCancelled else { return }
        for (account, _) in accounts {
            _ = await login(of: account, on: repos.first { $0.accountId == account.id }?.host, tokens: tokens)
        }

        let ids = Set(accounts.map { $0.account.id })
        noteAttention(tokens, among: ids)
        memberships = memberships.filter { ids.contains($0.key) }
        if logins.keys.contains(where: { !ids.contains($0) }) { logins = logins.filter { ids.contains($0.key) } }
        lastRefreshFailed = !outcomes.isEmpty && outcomes.allSatisfy { $0 == .offline }
        // Only a host that answered makes the pull requests newer.
        if outcomes.isEmpty || outcomes.contains(.answered) { lastRefreshedAt = now }
        guard !Task.isCancelled else { return }
        saveSnapshot()
    }

    /// Reads one repo's pull requests again, as after a merge from its detail
    /// (Ruling 14), and keeps the snapshot in step unless cancelled.
    func reload(repoKey: String) async {
        guard let repo = repos.first(where: { $0.id == repoKey }) else { return }
        let tokens = TokenBook(ask: environment.token)
        await tokens.prepare(repo.accountId)
        _ = await readPulls(of: [repo], tokens: tokens)
        guard !Task.isCancelled else { return }
        noteAttention(tokens, among: nil)
        saveSnapshot()
    }

    /// Takes `followed` as the repos to show. One that left loses its pull
    /// requests, its error and its detail store, as do the selection on it
    /// and the filter by it; a repo now read with another account loses its
    /// detail store. The Others stay, with their selection and detail store
    /// (R2 Ruling 9): one whose repo is followed takes the followed repo, and
    /// keeps its store unless that one is read with another account.
    private func adopt(_ followed: FollowedSet) {
        let after = Dictionary(followed.repos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let before = readers(followed: repos)
        let moved = others.map { InboxPull(repo: otherRepo($0.repo, followed: after), pull: $0.pull) }
        if moved != others { others = moved }
        let now = readers(followed: followed.repos)
        detailStores = detailStores.filter { key, _ in
            guard let current = now[key], let previous = before[key] else { return false }
            return current.accountId == previous.accountId && current.host == previous.host
        }
        repos = followed.repos
        droppedByLimit = followed.dropped
        pulls = pulls.filter { after[$0.key] != nil }
        repoErrors = repoErrors.filter { after[$0.key] != nil }
        latestRead = latestRead.filter { after[$0.key] != nil }
        if let selectedID, !after.keys.contains(where: { selectedID.hasPrefix($0 + "#") }),
           !others.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
        }
        if let repoFilter, after[repoFilter] == nil { self.repoFilter = nil }
    }

    /// The repo each key's detail store reads with: the followed one, else
    /// its Others'.
    private func readers(followed: [ReviewRepo]) -> [String: ReviewRepo] {
        Dictionary(others.map { ($0.repo.id, $0.repo) } + followed.map { ($0.id, $0) },
                   uniquingKeysWith: { _, last in last })
    }

    /// An Other's repo after a refresh (R2 Ruling 9): the followed one when
    /// its repo is followed; else its own as a repo that isn't, with the
    /// clone the refresh saw.
    private func otherRepo(_ repo: ReviewRepo, followed: [String: ReviewRepo]) -> ReviewRepo {
        if let followedRepo = followed[repo.id] { return followedRepo }
        var loose = repo
        loose.sources = []
        loose.lastActivity = nil
        loose.localURL = knownClones[repo.id]
        return loose
    }

    /// No account left: the inbox empties, the Others included, with what it
    /// knew of the accounts, and is saved empty. With nothing to clear,
    /// nothing is written.
    private func clearWithoutAccounts() {
        if lastRefreshFailed { lastRefreshFailed = false }
        guard !repos.isEmpty || !pulls.isEmpty || !repoErrors.isEmpty || !detailStores.isEmpty || !others.isEmpty
                || droppedByLimit > 0 || !memberships.isEmpty || !logins.isEmpty
                || !accountsNeedingAttention.isEmpty else { return }
        others = []
        otherGens = [:]
        adopt(FollowedSet(repos: [], dropped: 0))
        memberships = [:]
        logins = [:]
        accountsNeedingAttention = []
        saveSnapshot()
    }

    /// Accounts that gave a token leave `accountsNeedingAttention`; those to
    /// connect again join it. With `among`, accounts no longer there leave too.
    private func noteAttention(_ tokens: TokenBook, among ids: Set<UUID>?) {
        var attention = ids.map { accountsNeedingAttention.intersection($0) } ?? accountsNeedingAttention
        attention.subtract(tokens.answered)
        attention.formUnion(tokens.reconnect)
        if attention != accountsNeedingAttention { accountsNeedingAttention = attention }
    }

    // MARK: Discovery

    /// The repos `account` was recently active in, among those it belongs to
    /// (`members`; Rulings 2 and 3). `nil` when its membership, its login or
    /// its activity can't be read.
    private func recentActivity(of account: HostingAccount, on instance: HostingInstance, members: [RemoteRepoSummary]?,
                                tokens: TokenBook, now: Date) async -> [ActivityCandidate]? {
        guard let members else { return nil }
        let anyHost = members.lazy.compactMap { RemoteHost.make(fullName: $0.fullName, on: instance) }.first
        guard let login = await login(of: account, on: anyHost, tokens: tokens) else { return nil }
        let source = environment.makeActivity(instance.kind)
        let since = now.addingTimeInterval(-FollowedRepos.activityWindow)
        guard let hits = try? await withToken(account.id, tokens, { token in
            try await source.recentActivity(apiBase: instance.apiBaseURL, login: login, since: since, token: token)
        }) else { return nil }
        return Self.candidates(ActivityMatcher.match(hits, members: members), on: instance, accountId: account.id)
    }

    /// The repos `account` belongs to: the cached list within
    /// `membershipTTL`, else read again (Ruling 3). `nil` when it can't be
    /// read. Whether the list is complete comes with it (`isComplete`).
    private func membership(of account: HostingAccount, on instance: HostingInstance,
                            tokens: TokenBook, now: Date) async -> MembershipCache? {
        if let cached = memberships[account.id], now.timeIntervalSince(cached.fetchedAt) < Self.membershipTTL {
            return cached
        }
        let browser = environment.makeBrowser(instance.kind)
        guard let read = try? await withToken(account.id, tokens, { token in
            try await Self.allPages(of: browser, apiBase: instance.apiBaseURL, token: token)
        }) else { return nil }
        let list = MembershipCache(fetchedAt: now, repos: read.repos, isComplete: read.isComplete)
        memberships[account.id] = list
        return list
    }

    /// The user's login on `account` (Ruling 11): the account's own, else read
    /// once per session with `host`, a repo of the account.
    private func login(of account: HostingAccount, on host: RemoteHost?, tokens: TokenBook) async -> String? {
        if let login = account.login {
            if logins[account.id] != login { logins[account.id] = login }
            return login
        }
        if let host, !loginLookups.contains(account.id), tokens.current(account.id) != nil {
            loginLookups.insert(account.id)
            let provider = environment.makeProvider(host)
            if let user = try? await withToken(account.id, tokens, { token in
                try await provider.fetchCurrentUser(host: host, token: token)
            }) {
                logins[account.id] = user
            } else if Task.isCancelled {
                // Not a real try: the next round asks again.
                loginLookups.remove(account.id)
            }
        }
        return logins[account.id]
    }

    /// Runs `call` with the account's token; after a 401, one fresh token and
    /// one retry. `nil` when there's no token to run it with.
    private func withToken<T>(_ accountId: UUID, _ tokens: TokenBook,
                              _ call: (String) async throws -> T) async throws -> T? {
        guard let token = tokens.current(accountId) else { return nil }
        do {
            return try await call(token)
        } catch PullRequestFetchError.unauthorized {
            guard let fresh = await tokens.renew(accountId, rejected: token) else { return nil }
            do {
                return try await call(fresh)
            } catch PullRequestFetchError.unauthorized {
                tokens.reject(accountId)
                return nil
            }
        }
    }

    // MARK: Pull requests

    /// Reads the open pull requests of `targets`, `concurrency` at a time,
    /// keeping each answer as it lands (Ruling 6). A 401 gets one fresh
    /// token and one retry.
    private func readPulls(of targets: [ReviewRepo], tokens: TokenBook) async -> [ReadOutcome] {
        var outcomes: [ReadOutcome] = []
        var pending = targets[...]
        await withTaskGroup(of: PullsRead.self) { group in
            var running = 0
            while true {
                while running < Self.concurrency, !Task.isCancelled, let repo = pending.popFirst() {
                    guard let token = tokens.current(repo.accountId) else {
                        outcomes.append(tokens.isUnavailable(repo.accountId) ? .offline : .withheld)
                        continue
                    }
                    let (read, provider) = prepareRead(of: repo, token: token, isRetry: false)
                    group.addTask { await read.run(with: provider) }
                    running += 1
                }
                guard let read = await group.next() else { break }
                running -= 1
                if !read.isRetry, !Task.isCancelled, case .rejected = Self.failure(of: read),
                   let fresh = await tokens.renew(read.repo.accountId, rejected: read.token) {
                    let (retry, provider) = prepareRead(of: read.repo, token: fresh, isRetry: true)
                    group.addTask { await retry.run(with: provider) }
                    running += 1
                    continue
                }
                outcomes.append(apply(read, tokens: tokens))
            }
        }
        return outcomes
    }

    /// A read of `repo`, now its newest, and the provider to run it with.
    private func prepareRead(of repo: ReviewRepo, token: String,
                             isRetry: Bool) -> (PullsRead, any PullRequestProvider) {
        readCounter &+= 1
        latestRead[repo.id] = readCounter
        return (PullsRead(repo: repo, token: token, isRetry: isRetry, generation: readCounter),
                environment.makeProvider(repo.host))
    }

    /// Keeps one answer, unless a newer read of that repo started since.
    private func apply(_ read: PullsRead, tokens: TokenBook) -> ReadOutcome {
        let key = read.repo.id
        guard latestRead[key] == read.generation else { return .answered }
        guard let failure = Self.failure(of: read) else {
            if case .success(let list) = read.result { pulls[key] = list }
            repoErrors[key] = nil
            return .answered
        }
        switch failure {
        case .failed(let message):
            pulls[key] = nil
            repoErrors[key] = message
            return .answered
        case .offline:
            return .offline
        case .rejected:
            // The renewed token was rejected too.
            if read.isRetry { tokens.reject(read.repo.accountId) }
            return tokens.isUnavailable(read.repo.accountId) ? .offline : .withheld
        }
    }

    // MARK: Detail

    /// The store that opens `repoKey`'s pull requests, made on first use with
    /// the repo's account and kept while the repo is followed or an Other
    /// uses it. `nil` for a repo that's neither.
    func detailStore(for repoKey: String) -> PullRequestStore? {
        if let store = detailStores[repoKey] { return store }
        guard let repo = repos.first(where: { $0.id == repoKey })
                ?? others.first(where: { $0.repo.id == repoKey })?.repo else { return nil }
        let accountId = repo.accountId
        let host = repo.host
        let token = environment.token
        let auth: @MainActor (RemoteHost, String?) async -> PullRequestAuthResult = { _, rejected in
            await token(accountId, rejected)
        }
        let store = PullRequestStore(cli: nil, auth: auth, silentAuth: auth, resolveHost: { host },
                                     makeProvider: environment.makeProvider,
                                     makeReviewProvider: environment.makeReviewProvider)
        detailStores[repoKey] = store
        return store
    }

    /// Opens `item` in its repo's detail store once that has a token.
    func open(_ item: InboxPull) async {
        guard let store = detailStore(for: item.repo.id) else { return }
        openGen &+= 1
        let gen = openGen
        guard await store.prepareForDetail(), gen == openGen else { return }
        store.select(item.pull)
    }

    // MARK: Links

    /// What reading a link came to: its pull request and the account that
    /// read it, or why there's none.
    private enum LinkRead {
        case read(PullRequest, accountId: UUID)
        case unread(LinkOpenOutcome)
    }

    /// Opens the pull request `link` points to (R2 Rulings 9 to 11). A row
    /// of the inbox, followed or an Other, is revealed without a request; an
    /// Other opened again moves to the top. Otherwise the selection goes and
    /// `openingLink` names the link while its detail is read (`readLink`);
    /// the pull request then joins the Others, unless a refresh listed it
    /// meanwhile, and is selected. Read to no pull request, the selection
    /// that went comes back if the list still shows it and nothing was
    /// picked meanwhile. A later `openLink` wins: an earlier one that lands
    /// after it adds its row, but neither selects anything nor touches
    /// `openingLink`.
    func openLink(_ link: PullRequestLink) async -> LinkOpenOutcome {
        linkGen &+= 1
        let gen = linkGen
        let repoKey = FollowedRepos.key(link.host)
        let id = InboxPull.id(repoKey: repoKey, number: link.number)
        if reveal(id) {
            if let index = others.firstIndex(where: { $0.id == id }) {
                others.insert(others.remove(at: index), at: 0)
                otherGens[id] = gen
            }
            openingLink = nil
            return .opened(id)
        }
        let cleared = selectedID
        selectedID = nil
        openingLink = PendingLink(host: link.host, number: link.number)
        switch await readLink(link) {
        case .unread(let outcome):
            if gen == linkGen {
                openingLink = nil
                if selectedID == nil, let cleared {
                    selectedID = cleared
                    dropHiddenSelection()
                }
            }
            return outcome
        case .read(let pull, let accountId):
            // A refresh may have run meanwhile: the repo and the list as they are now.
            let item = InboxPull(repo: repoForLink(link, accountId: accountId), pull: pull)
            if !isListed(repoKey: repoKey, number: pull.number) { addOther(item, gen: gen) }
            if gen == linkGen {
                openingLink = nil
                reveal(item.id)
            }
            return .opened(item.id)
        }
    }

    /// The × of an Other (R2 Ruling 9): its row goes, with the selection if
    /// it was on it, and its repo's detail store once no row uses that repo.
    func closeOther(_ id: InboxPull.ID) {
        guard let item = others.first(where: { $0.id == id }) else { return }
        others.removeAll { $0.id == id }
        otherGens[id] = nil
        if selectedID == id { selectedID = nil }
        let repoKey = item.repo.id
        if !repos.contains(where: { $0.id == repoKey }), !others.contains(where: { $0.repo.id == repoKey }) {
            detailStores[repoKey] = nil
        }
    }

    /// The pull request an Other's detail holds (R2 Ruling 9): merged or
    /// closed there, its row shows it. A row of the followed list is read
    /// again instead (`reload(repoKey:)`).
    func noteDetail(_ pull: PullRequest, for id: InboxPull.ID) {
        guard let index = others.firstIndex(where: { $0.id == id }),
              others[index].pull.number == pull.number, others[index].pull != pull else { return }
        others[index] = InboxPull(repo: others[index].repo, pull: pull)
    }

    /// Reads `link`'s pull request with the first account that can see it
    /// (R2 Ruling 10), in `linkAccounts` order. A 404 or a 403 moves on to
    /// the next account, a 401 renews the token and retries once, and any
    /// other error stops. When none reads it: connecting an account if one
    /// must be connected again or there's none, else why it's hidden, else
    /// why there was no token.
    private func readLink(_ link: PullRequestLink) async -> LinkRead {
        let accounts = linkAccounts(link)
        guard !accounts.isEmpty else { return .unread(.connectAccount(instanceId: link.instanceId)) }
        let provider = environment.makeProvider(link.host)
        let tokens = TokenBook(ask: environment.token)
        var hidden: PullRequestFetchError?
        for accountId in accounts {
            await tokens.prepare(accountId)
            do {
                if let detail = try await withToken(accountId, tokens, { token in
                    try await provider.fetchDetail(host: link.host, number: link.number, token: token)
                }) {
                    return .read(detail.pull, accountId: accountId)
                }
            } catch let error as PullRequestFetchError where error == .notFound || error == .forbidden {
                hidden = hidden ?? error
            } catch {
                return .unread(.failed(PullRequestStore.message(for: error)))
            }
        }
        if !tokens.reconnect.isEmpty { return .unread(.connectAccount(instanceId: link.instanceId)) }
        if let hidden {
            let reference = "\(link.host.slug) \(link.host.provider.reference(link.number))"
            return .unread(.failed("\(reference) — \(PullRequestStore.message(for: hidden))"))
        }
        return .unread(.failed(tokens.failure ?? String(localized: "Request failed")))
    }

    /// The accounts that may read a link (R2 Ruling 10): a followed repo's
    /// own; else its instance's, those that sign first with the owner's
    /// login at their head, then those to connect again.
    private func linkAccounts(_ link: PullRequestLink) -> [UUID] {
        if let repo = repos.first(where: { $0.id == FollowedRepos.key(link.host) }) { return [repo.accountId] }
        let onInstance = environment.accounts().filter { $0.instance.id == link.instanceId }.map(\.account)
        let signing = onInstance.filter { AccountGitCredentials.signs($0) }
        let rest = onInstance.filter { !AccountGitCredentials.signs($0) }
        return (FollowedRepos.accountsInPreference(for: link.host, among: signing) + rest).map(\.id)
    }

    /// The repo a link's pull request shows with (R2 Ruling 9): the followed
    /// one; else one that isn't followed, read with `accountId`, cloned from
    /// its membership's URL when known, and with the clone the last refresh
    /// saw.
    private func repoForLink(_ link: PullRequestLink, accountId: UUID) -> ReviewRepo {
        let repoKey = FollowedRepos.key(link.host)
        if let followed = repos.first(where: { $0.id == repoKey }) { return followed }
        let member = memberships[accountId]?.repos.first { $0.fullName.lowercased() == link.host.slug.lowercased() }
        return ReviewRepo(host: link.host, accountId: accountId, sources: [], lastActivity: nil,
                          cloneURL: member?.httpsURL ?? FollowedRepos.cloneURL(for: link.host),
                          localURL: knownClones[repoKey])
    }

    /// Puts `item` among the Others by opening order (`gen`), in place of the
    /// row it had. The Others of a repo share one repo, which their detail
    /// store reads with: a read with another account takes them all over,
    /// and the store goes.
    private func addOther(_ item: InboxPull, gen: UInt64) {
        var rows = others.filter { $0.id != item.id }
        if let shared = rows.first(where: { $0.repo.id == item.repo.id })?.repo,
           shared.accountId != item.repo.accountId || shared.host != item.repo.host {
            rows = rows.map { $0.repo.id == item.repo.id ? InboxPull(repo: item.repo, pull: $0.pull) : $0 }
            detailStores[item.repo.id] = nil
        }
        otherGens[item.id] = gen
        let index = rows.firstIndex { otherGens[$0.id, default: 0] < gen } ?? rows.count
        rows.insert(item, at: index)
        others = rows
    }

    // MARK: Auto refresh

    /// Refreshes every `autoRefreshInterval` while `isOnline` and `isActive`
    /// hold. Replaces a loop already running.
    func startAutoRefresh(isOnline: @escaping @MainActor () -> Bool, isActive: @escaping @MainActor () -> Bool) {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.autoRefreshInterval)
                guard !Task.isCancelled, let self else { return }
                if isOnline(), isActive() { await self.refresh(force: true) }
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }
}
