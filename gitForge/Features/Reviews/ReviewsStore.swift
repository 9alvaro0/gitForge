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
    /// stands out (`LocalRemote.assignedAccountId`), and the account to
    /// reconnect it waits for, if any (`LocalRemote.waitingAccountId`);
    /// nobody is asked. Which of them the inbox follows is not decided here:
    /// `FollowedRepos.merge` keeps a clone only if an account of its instance
    /// belongs to the repo, when the memberships tell, and the refresh first
    /// looks for the ones that were renamed. A refresh cancelled while this
    /// runs commits nothing: `GitCLI` reads the remotes with `try?`, so a
    /// cancelled read comes back empty.
    var localRemotes: @MainActor () async -> [LocalRemote]
    /// An account's token; `rejected` is one that just got a 401.
    var token: @MainActor (_ accountId: UUID, _ rejected: String?) async -> PullRequestAuthResult
    var makeProvider: @MainActor (RemoteHost) -> PullRequestProvider
    var makeBrowser: @MainActor (HostingInstance.Kind) -> any RemoteRepoBrowsing
    var makeActivity: @MainActor (HostingInstance.Kind) -> any ReviewActivitySource
    /// Where a renamed or moved repo lives now (R3 Ruling 10), and the
    /// searches of a whole host.
    var makeSearch: @MainActor (HostingInstance.Kind) -> any HostSearching
    var snapshots: ReviewsSnapshotStore
    /// The user's patterns, repos followed by hand and hidden repos
    /// (`reviews-settings.json`), read once when the store is made.
    var config: ReviewsConfigStore
    var now: @MainActor () -> Date = { .now }
    /// The writes of the detail stores: reviews, threads, merge.
    var makeReviewProvider: @MainActor (RemoteHost) -> PullRequestReviewProvider = {
        PullRequestReviewProviderFactory.make(for: $0)
    }
    /// The tab the Pull requests section was left on, read once when the
    /// store is made (U1 Ruling 2); `nil` when none was saved or it can't be read.
    var loadTab: @MainActor () -> PullsTab? = { nil }
    /// Saves the tab each time it changes.
    var saveTab: @MainActor (PullsTab) -> Void = { _ in }
    /// The repository open in gitForge and its pull requests store, if there
    /// is one (U1 Ruling 3). Read every time it's needed: opening another
    /// repository changes it.
    var activeRepository: @MainActor () -> ActiveRepositoryPulls? = { nil }
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
    /// Most clones asked about in one refresh, to follow a rename (R3 Ruling 10).
    static let renameLookups = 20
    /// How long a clone whose lookup failed waits before it's asked about
    /// again, but for the Refresh button (R3 Ruling X).
    static let failedLookupBackoff: TimeInterval = 3600

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
    /// The keys (`FollowedRepos.key`) of the repos `FollowedRepos.limit`
    /// leaves out: followed, only not loaded (R3 Ruling U).
    private(set) var droppedKeys: Set<String> = []
    /// Repos left out by `FollowedRepos.limit`.
    var droppedByLimit: Int { droppedKeys.count }
    private(set) var isRefreshing = false
    /// When the pull requests were last read; at launch, the snapshot's date.
    private(set) var lastRefreshedAt: Date?
    /// The last refresh reached no repo, for lack of network.
    private(set) var lastRefreshFailed = false
    /// Which half of the inbox shows. Under a `repositoryList` it's the half
    /// the inbox goes back to; it is what `tab` reads while that is `nil`.
    var filter: ReviewsFilter = .team {
        didSet { saveTabIfChanged() }
    }
    /// The open repository's list the section shows instead of the inbox
    /// (U1 Ruling 2); `nil` shows the inbox, by `filter`. Set through `tab`;
    /// `reveal(_:)`, `showRepo(_:)` and `showAllRepos()` take the section
    /// back to the inbox, and so do `openLink(_:)` and `openFoundRepo(_:)` as
    /// their reads start (U1 Ruling M), though closing a repo filter with
    /// nothing selected brings the list back.
    private(set) var repositoryList: PullListState? {
        didSet { saveTabIfChanged() }
    }
    /// The repo the inbox is narrowed to (`ReviewRepo.id`), with the pull
    /// requests of both halves; `nil` shows every repo, by `filter` (R2
    /// Ruling 7). `showRepo(_:)` sets it; `showAllRepos()`, `reveal(_:)` and
    /// a refresh that stops following the repo clear it.
    private(set) var repoFilter: String?
    var selectedID: InboxPull.ID?
    /// The row the list scrolls into view, set each time the inbox selects or
    /// keeps a row from outside the list: `reveal` (a ⌘K pick, a link that
    /// lands), `showRepo` and `showAllRepos`. A click on a row only sets
    /// `selectedID`: that row is in view already.
    private(set) var revealRequest: ReviewsRevealRequest?
    /// Pull requests opened from a link that weren't rows of the followed
    /// list when they landed, by opening order, the last one first (R2
    /// Ruling 9). Only for the session: they never reach the snapshot.
    private(set) var others: [InboxPull] = []
    /// The link `openLink` is reading, while it does (R2 Ruling 11).
    private(set) var openingLink: PendingLink?
    /// The row whose detail store couldn't get ready the last time `open`
    /// opened it: no host (the open repository's `origin` isn't on a declared
    /// instance), no token, no account chosen or an error, as the store says.
    /// The detail then shows why, with a way to try again, instead of waiting.
    /// The next `open` clears it.
    private(set) var unpreparedDetail: InboxPull.ID?
    /// The user's patterns, repos followed by hand, hidden repos and
    /// answered proposals (R3 Ruling 8), as `reviews-settings.json` keeps
    /// them. Only `applyConfig` and `storeConfig` change it; the follow API
    /// in `ReviewsStore+Follow.swift` goes through them.
    private(set) var config: ReviewsConfig
    /// The pattern the inbox offers until it's answered (R3 Ruling 3), worked
    /// out again by every refresh and every change of `config`.
    private(set) var proposal: PatternProposal?
    /// Each instance's last "Search all of <host>" (R3 Ruling 12), by
    /// instance id. Only for the session.
    private(set) var hostSearches: [UUID: HostSearchState] = [:]
    /// Repos opened from a search that aren't followed (R3 Ruling 13), the
    /// last one opened last: `repoFilter` may name one, and its open pull
    /// requests are among the Others. One that comes to be followed leaves.
    /// Only for the session.
    private(set) var browsedRepos: [ReviewRepo] = []
    /// The last link `openLink` couldn't read for want of an account, to open
    /// again once one is connected (R3 Ruling 14). Every `openLink` clears it
    /// and `retryPendingLink` takes it; a refresh without accounts keeps it,
    /// since connecting the first account is what it waits for.
    private(set) var pendingLink: PullRequestLink?

    private let environment: ReviewsEnvironment
    /// Each account's membership list, kept past `membershipTTL` when it
    /// can't be read again. Written by the refresh, the snapshot,
    /// `clearWithoutAccounts` and `searchHost` (an account with no list yet);
    /// `ReviewsStore+Follow.swift` reads it.
    @ObservationIgnored private(set) var memberships: [UUID: MembershipCache] = [:]
    /// What the last refresh's `FollowedRepos.merge` took besides `config`
    /// (R3 Ruling 7): a change of the settings merges again on it, without
    /// the network. `nil` before the first refresh and without accounts.
    @ObservationIgnored private(set) var lastRound: FollowRound?
    /// Where the clones the membership leaves out live now, by the clone's
    /// `FollowedRepos.key` (R3 Ruling 10): only those of the last round's
    /// clones, kept in the snapshot.
    @ObservationIgnored private var lookups: [String: RepoLookup] = [:]
    /// When the last lookup of each of those clones failed, by key, if it did
    /// since its last answer (R3 Ruling X). Only for the session: a launch
    /// asks again.
    @ObservationIgnored private var failedLookups: [String: Date] = [:]
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
    /// The last `revealRequest.serial`.
    @ObservationIgnored private var revealSerial: UInt64 = 0
    /// The newest search started on each instance: an older one that lands
    /// later is dropped (R3 Review Focus 5).
    @ObservationIgnored private var latestSearch: [UUID: UInt64] = [:]
    @ObservationIgnored private var searchCounter: UInt64 = 0
    @ObservationIgnored private var autoRefreshTask: Task<Void, Never>?
    /// The tab as it was last saved, or read at launch: a change of `filter`
    /// or `repositoryList` saves only if it moves `tab` off this.
    @ObservationIgnored private var lastTab: PullsTab = .team
    /// The `repositoryList` narrowing the inbox to a repo took off the
    /// section, for `showAllRepos()` to bring back (U1 Ruling 2).
    @ObservationIgnored private var listSetAside: PullListState?

    init(environment: ReviewsEnvironment) {
        self.environment = environment
        self.config = environment.config.load()
        // What was read is not a change to save: `lastTab` is already it when
        // the setter, which moves the tab in one step, runs.
        if let saved = environment.loadTab() {
            lastTab = saved
            tab = saved
        }
    }

    // MARK: Reading

    var hasAccounts: Bool { !environment.accounts().isEmpty }

    /// The accounts the inbox reads with, with their instance, in store
    /// order (`ReviewsEnvironment.accounts`).
    var inboxAccounts: [(account: HostingAccount, instance: HostingInstance)] { environment.accounts() }

    /// The repository open in gitForge, if any (`ReviewsEnvironment.activeRepository`);
    /// `ReviewsStore+Active.swift` says what the inbox makes of it.
    var activeRepository: ActiveRepositoryPulls? { environment.activeRepository() }

    /// The accounts of `accountsNeedingAttention` that own at least one
    /// followed repo, with their instance, in store order, for the inbox's
    /// "Reconnect" notices. A stale token saved next to working accounts, with
    /// no repo of its own, is still in `accountsNeedingAttention` but says
    /// nothing here: there's nothing in the inbox to reconnect it for. One
    /// whose repos are still listed (activity repos carried over, a clone
    /// that waits for it) keeps its notice (spec §4.2): a clone that waits for
    /// it stays even where the membership doesn't list the repo, until it's
    /// connected again (R3 Ruling 11). One that was removed meanwhile is left
    /// out.
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

    /// The current filter's groups, by their newest update, with the open
    /// repository's first (U1 Ruling 3), then the repos that failed with
    /// nothing to show (Rulings 8 and 9). With `repoFilter`, only that repo's,
    /// whoever opened the pull requests (R2 Ruling 7); on a browsed repo, its
    /// Others (R3 Ruling 13).
    var groups: [ReviewGroup] {
        if let browsed = filteredBrowsedRepo { return browsedGroups(browsed) }
        return groups(of: filter, narrowedTo: repoFilter)
    }

    /// The groups `half` lists, as `groups` has them, whatever the inbox
    /// shows: `count(for:)` reads each half this way, without the repo filter.
    /// With `repoKey`, only that repo's, with the pull requests of both halves.
    private func groups(of half: ReviewsFilter, narrowedTo repoKey: String? = nil) -> [ReviewGroup] {
        var loaded: [(group: ReviewGroup, newest: Date)] = []
        var failed: [ReviewGroup] = []
        let isOneRepo = repoKey != nil
        for repo in repos where !isOneRepo || repo.id == repoKey {
            let rows = (pulls[repo.id] ?? [])
                .filter { isOneRepo || isMine($0, accountId: repo.accountId) == (half == .mine) }
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
        return placingActiveFirst(ordered.map(\.group), of: half, narrowed: isOneRepo) + failed
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
    /// nothing about what the list shows. A browsed repo is never unread: its
    /// pull requests, read when it was opened, are its Others.
    private var hasUnreadRepos: Bool {
        if filteredBrowsedRepo != nil { return false }
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

    /// The number the tab of `half` shows (U1 Ruling 6, spec §4.2): the rows
    /// it lists in every repo, whatever the repo filter, drafts and the open
    /// repository included, and its Others that aren't rows of the list. So it
    /// can be more than `badgeCount`. `nil` without accounts, or while nothing
    /// has been read yet: the tab then shows no number.
    func count(for half: ReviewsFilter) -> Int? {
        guard hasAccounts, lastRefreshedAt != nil else { return nil }
        let rows = groups(of: half).reduce(0) { $0 + $1.pulls.count }
        let unlisted = others.filter { !isListed(repoKey: $0.repo.id, number: $0.pull.number) }
        return rows + unlisted.count(where: { isMine($0) == (half == .mine) })
    }

    // Not private: `ReviewsStore+Active.swift` reads this one.
    func isMine(_ pull: PullRequest, accountId: UUID) -> Bool {
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

    // MARK: Tab

    /// The tab the section is on: `repositoryList` when it shows one, else
    /// the inbox's `filter` (U1 Ruling 2). Writing it sets both and is saved
    /// once; so is any other change of `filter` that moves it. Open and Closed
    /// are the repository's: they leave a repo filter, and the half goes back
    /// to Team, so without a repository, where the view falls back to Team
    /// (`PullsTab.shown(_:hasRepository:)`), it isn't a Mine left under them.
    /// The saved tab isn't what the view shows without a repository open.
    var tab: PullsTab {
        get { PullsTab(half: filter, repositoryList: repositoryList) }
        set {
            if let half = newValue.half {
                // The half first: while a list shows, a half doesn't move the
                // tab, and the list's going is then the only change.
                filter = half
                repositoryList = nil
            } else {
                // The list first, for the same reason the other way round: the
                // half moving under it is then no change of tab.
                repositoryList = newValue.repositoryList
                filter = .team
                repoFilter = nil
                listSetAside = nil
            }
        }
    }

    private func saveTabIfChanged() {
        let current = tab
        guard current != lastTab else { return }
        lastTab = current
        environment.saveTab(current)
    }

    // MARK: Selection and repo filter

    /// Selects `id` from outside the list (R2 Ruling 8) and asks the list to
    /// scroll to it (`revealRequest`). For a row of a followed repo or of the
    /// open repository, or an Other, the inbox moves to the half that shows
    /// it, Mine if it's the user's and Team if not, and drops the filter by a
    /// repo other than its own; the filter by repo hides the Others, so for
    /// an Other it is dropped unless it's on the Other's own browsed repo,
    /// which shows them (R3 Ruling 13). `false`, with nothing changed, when
    /// `id` is none of them.
    @discardableResult
    func reveal(_ id: InboxPull.ID) -> Bool {
        if let item = inboxRows.first(where: { $0.id == id }) {
            filter = half(showing: item)
            if let repoFilter, repoFilter != item.repo.id { self.repoFilter = nil }
        } else if let item = others.first(where: { $0.id == id }) {
            filter = half(showing: item)
            if filteredBrowsedRepo?.id != item.repo.id { repoFilter = nil }
        } else {
            return false
        }
        // After the half, so the tab moves once.
        repositoryList = nil
        selectedID = id
        requestReveal(id)
        return true
    }

    /// Narrows the inbox to the followed repo `repoKey` (R2 Ruling 7); any
    /// other key changes nothing. The selection stays, scrolled into view, if
    /// it's one of that repo's pull requests, and goes if not.
    func showRepo(_ repoKey: String) {
        guard repos.contains(where: { $0.id == repoKey }) else { return }
        narrow(to: repoKey)
    }

    /// Narrows the inbox to `repoKey`, followed or browsed: the selection
    /// stays, scrolled into view, if it's one of that repo's pull requests,
    /// and goes if not. The section leaves the repository's list for the
    /// inbox; the first narrowing sets the list aside, for `showAllRepos()`
    /// to bring back, or `leftList`, the one a read that narrows left when
    /// it started (`openFoundRepo`), and moving to another repo keeps what it
    /// set aside.
    private func narrow(to repoKey: String, leftList: PullListState? = nil) {
        if repoFilter == nil { listSetAside = repositoryList ?? leftList }
        repositoryList = nil
        repoFilter = repoKey
        guard let selectedID else { return }
        if selectedID.hasPrefix(repoKey + "#") {
            requestReveal(selectedID)
        } else {
            self.selectedID = nil
        }
    }

    /// Shows every repo again, the × of the filter bar (R2 Ruling 7). The
    /// repo's view showed both halves, so a row picked there stays selected:
    /// the inbox moves to the half that shows it, as `reveal` does, and the
    /// list scrolls to it. With nothing selected the section goes back to the
    /// tab it had before the filter, a repository's list included (U1
    /// Ruling 2); with a selection it stays on the inbox.
    func showAllRepos() {
        let setAside = listSetAside
        listSetAside = nil
        repoFilter = nil
        guard let selectedID else {
            if let setAside { repositoryList = setAside }
            return
        }
        if let item = inboxRows.first(where: { $0.id == selectedID }) ?? others.first(where: { $0.id == selectedID }) {
            filter = half(showing: item)
            requestReveal(selectedID)
        }
        repositoryList = nil
    }

    /// Takes the section off the repository's list to the inbox, on the half
    /// it had, saved once (Ruling B), as a read from ⌘K starts (U1 Ruling M):
    /// what it opens shows in the inbox, and so does that it's being read.
    /// The list it left, if one showed.
    @discardableResult
    private func leaveRepositoryList() -> PullListState? {
        guard let list = repositoryList else { return nil }
        repositoryList = nil
        return list
    }

    /// Mine for the user's own pull request, Team for anyone else's: the half
    /// of the list that shows it, an Other included.
    private func half(showing item: InboxPull) -> ReviewsFilter {
        isMine(item) ? .mine : .team
    }

    private func requestReveal(_ id: InboxPull.ID) {
        revealSerial &+= 1
        revealRequest = ReviewsRevealRequest(id: id, serial: revealSerial)
    }

    // MARK: Snapshot

    /// The last read, from disk: what the inbox shows before the network answers.
    func loadSnapshot() {
        guard let snapshot = environment.snapshots.load() else { return }
        repos = snapshot.repos
        pulls = snapshot.pulls
        memberships = snapshot.memberships
        logins = snapshot.logins
        lookups = snapshot.lookups ?? [:]
        lastRefreshedAt = snapshot.savedAt
    }

    /// Writes what's loaded, dated by the last refresh that reached the
    /// hosts. Nothing before one did.
    private func saveSnapshot() {
        guard let lastRefreshedAt else { return }
        environment.snapshots.save(ReviewsSnapshot(version: ReviewsSnapshot.currentVersion, savedAt: lastRefreshedAt,
                                                   repos: repos, pulls: pulls, memberships: memberships,
                                                   logins: logins, lookups: lookups.isEmpty ? nil : lookups))
    }

    // MARK: Refresh

    /// Works out the repos followed and reads their open pull requests. Does
    /// nothing while one runs, nor within `reloadThrottle` of the last unless
    /// forced. A cancelled round (Reviews left, the auto refresh stopped)
    /// writes nothing to disk. Without accounts it reads nothing, not even
    /// the clones: it only empties what removed accounts left.
    ///
    /// The memberships and the rename lookups are read again once a day;
    /// `rereadLists`, the Refresh button's, reads them again now (R3 Ruling 9).
    func refresh(force: Bool = false, rereadLists: Bool = false) async {
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
            let list = await membership(of: account, on: instance, tokens: tokens, now: now, rereadLists: rereadLists)
            lists[account.id] = list
            activity += await recentActivity(of: account, on: instance, members: list?.repos, tokens: tokens, now: now)
                ?? Self.carriedOver(repos, accountId: account.id)
        }
        let clones = await environment.localRemotes()
        // Cancelled, the clones may have come back empty: nothing is
        // committed, and the round doesn't count for the throttle.
        guard !Task.isCancelled else {
            lastRoundAt = previousRound
            return
        }
        let memberKeys = Self.memberKeys(accounts: accounts, lists: lists)
        // What keeps a clone the membership leaves out, as in `merge`: the
        // activity and the repos the user chose. Such a clone isn't looked
        // up, so it isn't followed under a new path too.
        let vouched = FollowedRepos.vouchedKeys(activity: activity,
                                                chosen: chosenCandidates(config, accounts: accounts),
                                                accounts: Self.signingFirst(accounts.map { $0.account }),
                                                instances: accounts.map { $0.instance })
        let local = await followRenames(of: clones, accounts: accounts, memberKeys: memberKeys, vouched: vouched,
                                        tokens: tokens, now: now, rereadLists: rereadLists)
        // Cancelled while looking up, a renamed clone may have missed its
        // path: nothing is committed either.
        guard !Task.isCancelled else {
            lastRoundAt = previousRound
            return
        }
        // A renamed clone under both paths: a link may still have the old one.
        knownClones = Dictionary((local + clones).map { (FollowedRepos.key($0.host), $0.repository.url) },
                                 uniquingKeysWith: { first, _ in first })
        let round = FollowRound(local: local, activity: activity, accounts: accounts, memberKeys: memberKeys)
        lastRound = round
        adopt(followed(in: round, with: config))
        updateProposal()

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
    /// keeps its store unless that one is read with another account. A
    /// browsed repo that's followed now leaves `browsedRepos`, and the filter
    /// by it stays (R3 Ruling 13).
    private func adopt(_ followed: FollowedSet) {
        let after = Dictionary(followed.repos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let before = readers(followed: repos)
        let moved = others.map { InboxPull(repo: otherRepo($0.repo, followed: after), pull: $0.pull) }
        if moved != others { others = moved }
        let browsed = browsedRepos.filter { after[$0.id] == nil }.map { otherRepo($0, followed: after) }
        if browsed != browsedRepos { browsedRepos = browsed }
        let now = readers(followed: followed.repos)
        detailStores = detailStores.filter { key, _ in
            guard let current = now[key], let previous = before[key] else { return false }
            return current.accountId == previous.accountId && current.host == previous.host
        }
        repos = followed.repos
        if droppedKeys != followed.droppedKeys { droppedKeys = followed.droppedKeys }
        pulls = pulls.filter { after[$0.key] != nil }
        repoErrors = repoErrors.filter { after[$0.key] != nil }
        latestRead = latestRead.filter { after[$0.key] != nil }
        if let selectedID, !after.keys.contains(where: { selectedID.hasPrefix($0 + "#") }),
           !others.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
        }
        if let repoFilter, after[repoFilter] == nil, !browsedRepos.contains(where: { $0.id == repoFilter }) {
            self.repoFilter = nil
        }
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
    /// nothing is written. The user's settings stay; the round and the
    /// proposal go, and so do the browsed repos and the searches, which an
    /// older one landing later doesn't bring back (R3 Ruling 13). The pending
    /// link stays: a link pasted before any account is connected waits for
    /// the first one (R3 Ruling 14).
    private func clearWithoutAccounts() {
        if lastRefreshFailed { lastRefreshFailed = false }
        lastRound = nil
        failedLookups = [:]
        if proposal != nil { proposal = nil }
        latestSearch = [:]
        if !hostSearches.isEmpty { hostSearches = [:] }
        if !browsedRepos.isEmpty {
            if filteredBrowsedRepo != nil { repoFilter = nil }
            browsedRepos = []
        }
        guard !repos.isEmpty || !pulls.isEmpty || !repoErrors.isEmpty || !detailStores.isEmpty || !others.isEmpty
                || droppedByLimit > 0 || !memberships.isEmpty || !logins.isEmpty || !lookups.isEmpty
                || !accountsNeedingAttention.isEmpty else { return }
        others = []
        otherGens = [:]
        adopt(FollowedSet(repos: [], droppedKeys: []))
        memberships = [:]
        logins = [:]
        lookups = [:]
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

    // MARK: Follow settings

    /// Takes `next` as the user's settings and applies them (R3 Ruling 7):
    /// saves them, merges again on `lastRound` without the network, adopts
    /// the result, reads the pull requests of the repos that have none yet
    /// and saves the snapshot. Before the first refresh there's no round to
    /// merge on: a forced refresh does it all. No limit is checked here; the
    /// follow API in `ReviewsStore+Follow.swift` checks it first.
    func applyConfig(_ next: ReviewsConfig) async {
        config = next
        environment.config.save(next)
        guard let lastRound else {
            await refresh(force: true)
            return
        }
        adopt(followed(in: lastRound, with: next))
        updateProposal()
        let unread = repos.filter(isUnread)
        if !unread.isEmpty {
            let tokens = TokenBook(ask: environment.token)
            for repo in unread { await tokens.prepare(repo.accountId) }
            _ = await readPulls(of: unread, tokens: tokens)
            guard !Task.isCancelled else { return }
            noteAttention(tokens, among: nil)
        }
        saveSnapshot()
    }

    /// Takes `next` as the user's settings when the change moves no repo
    /// (an answered proposal): saves them and works out the proposal again.
    func storeConfig(_ next: ReviewsConfig) {
        config = next
        environment.config.save(next)
        updateProposal()
    }

    private func updateProposal() {
        let next = nextProposal()
        if next != proposal { proposal = next }
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
    /// `membershipTTL`, else read again (Ruling 3). With `rereadLists` it's
    /// read again anyway, and the cached list stands in if that read fails
    /// (R3 Ruling 9). `nil` when it can't be read and no list of the day is
    /// cached. Whether the list is complete comes with it (`isComplete`).
    private func membership(of account: HostingAccount, on instance: HostingInstance,
                            tokens: TokenBook, now: Date, rereadLists: Bool) async -> MembershipCache? {
        let cached = memberships[account.id].flatMap { list in
            now.timeIntervalSince(list.fetchedAt) < Self.membershipTTL ? list : nil
        }
        if let cached, !rereadLists { return cached }
        guard let list = try? await readMembership(of: account, on: instance, tokens: tokens, now: now) else {
            return cached
        }
        return list
    }

    /// Reads the repos `account` belongs to now and keeps the list in
    /// `memberships`. `nil` when there's no token to read with; a read that
    /// fails throws.
    private func readMembership(of account: HostingAccount, on instance: HostingInstance,
                                tokens: TokenBook, now: Date) async throws -> MembershipCache? {
        let browser = environment.makeBrowser(instance.kind)
        guard let read = try await withToken(account.id, tokens, { token in
            try await Self.allPages(of: browser, apiBase: instance.apiBaseURL, token: token)
        }) else { return nil }
        let list = MembershipCache(fetchedAt: now, repos: read.repos, isComplete: read.isComplete)
        memberships[account.id] = list
        return list
    }

    /// The clones as `merge` takes them, a renamed one under its current path
    /// (R3 Ruling 10). Asks about the due ones (`renameTargets`) with the
    /// accounts that gave a token, keeps the answers in `lookups` and notes
    /// the failures in `failedLookups` (Ruling X); both hold only these
    /// clones. Failures of a cancelled round aren't noted: they're the
    /// cancel's.
    private func followRenames(of local: [LocalRemote],
                               accounts: [(account: HostingAccount, instance: HostingInstance)],
                               memberKeys: [UUID: Set<String>], vouched: Set<String>, tokens: TokenBook,
                               now: Date, rereadLists: Bool) async -> [LocalRemote] {
        let keys = Set(local.map { FollowedRepos.key($0.host) })
        lookups = lookups.filter { keys.contains($0.key) }
        failedLookups = failedLookups.filter { keys.contains($0.key) }
        let asking = Set(accounts.map(\.account.id).filter { tokens.current($0) != nil })
        let targets = Self.renameTargets(local, accounts: accounts, memberKeys: memberKeys, vouched: vouched,
                                         lookups: lookups, failures: failedLookups, asking: asking, now: now,
                                         rereadLists: rereadLists)
        let answers = await Self.lookUpPaths(targets, tokens: tokens, makeSearch: environment.makeSearch)
        for (key, path) in answers.found {
            lookups[key] = RepoLookup(fetchedAt: now, currentPath: path)
            failedLookups[key] = nil
        }
        if !Task.isCancelled {
            for key in answers.failed { failedLookups[key] = now }
        }
        return Self.renamed(local, instances: accounts.map(\.instance), memberKeys: memberKeys, vouched: vouched,
                            lookups: lookups)
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
    /// token and one retry. A change of the settings meanwhile may stop
    /// following a target: one not started by then isn't read, and `apply`
    /// drops what lands for one that left.
    private func readPulls(of targets: [ReviewRepo], tokens: TokenBook) async -> [ReadOutcome] {
        var outcomes: [ReadOutcome] = []
        var pending = targets[...]
        await withTaskGroup(of: PullsRead.self) { group in
            var running = 0
            while true {
                while running < Self.concurrency, !Task.isCancelled, let repo = pending.popFirst() {
                    guard repos.contains(where: { $0.id == repo.id }) else { continue }
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

    /// Keeps one answer, unless a newer read of that repo started since or
    /// the repo is no longer followed.
    private func apply(_ read: PullsRead, tokens: TokenBook) -> ReadOutcome {
        let key = read.repo.id
        guard latestRead[key] == read.generation, repos.contains(where: { $0.id == key }) else { return .answered }
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

    /// The store that opens `repoKey`'s pull requests: the open repository's
    /// own, which carries its local actions, whether the repo is followed, a
    /// visitor or the repo of an Other (U1 Ruling 4); else one made on first
    /// use with the repo's account and kept while the repo is followed or an
    /// Other uses it. `nil` for a repo that's none of those.
    func detailStore(for repoKey: String) -> PullRequestStore? {
        if repoKey == activeRepoKey, let store = activeRepository?.store { return store }
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

    /// Opens `item` in its repo's detail store once that has a token; one
    /// that can't get ready marks it `unpreparedDetail`. The open
    /// repository's own store may have it open already, from its Open tab:
    /// selecting it again would only read the detail over, so it's left (U1
    /// Ruling F). The inbox's own stores select every time.
    func open(_ item: InboxPull) async {
        guard let store = detailStore(for: item.repo.id) else { return }
        openGen &+= 1
        let gen = openGen
        if unpreparedDetail != nil { unpreparedDetail = nil }
        let prepared = await store.prepareForDetail()
        guard gen == openGen else { return }
        guard prepared else {
            unpreparedDetail = item.id
            return
        }
        guard store !== activeRepository?.store || store.selected?.number != item.pull.number else { return }
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
    /// the section leaves a repository's list for the inbox at once, on the
    /// half it had, so the link shows it's being opened whatever the tab (U1
    /// Ruling M), and doesn't go back to the list if the read fails. The pull
    /// request then joins the Others, unless a refresh listed it meanwhile,
    /// and is selected. Read to no pull request, the selection that went
    /// comes back if the list still shows it and nothing was picked
    /// meanwhile. A later `openLink` wins: an earlier one that lands after it
    /// adds its row, but neither selects anything nor touches `openingLink`.
    /// One that asks to connect an account keeps its link in `pendingLink`,
    /// unless a later one started meanwhile (R3 Ruling 14).
    func openLink(_ link: PullRequestLink) async -> LinkOpenOutcome {
        linkGen &+= 1
        let gen = linkGen
        if pendingLink != nil { pendingLink = nil }
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
        leaveRepositoryList()
        switch await readLink(link) {
        case .unread(let outcome):
            if gen == linkGen {
                openingLink = nil
                if selectedID == nil, let cleared {
                    selectedID = cleared
                    dropHiddenSelection()
                }
                if case .connectAccount = outcome { pendingLink = link }
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
    /// (R2 Ruling 10; `readWithAccounts`). When none reads it: connecting an
    /// account if one must be connected again or there's none, else why it's
    /// hidden, else why there was no token.
    private func readLink(_ link: PullRequestLink) async -> LinkRead {
        let provider = environment.makeProvider(link.host)
        let read = await readWithAccounts(readAccounts(for: link.host, instanceId: link.instanceId)) { token in
            try await provider.fetchDetail(host: link.host, number: link.number, token: token)
        }
        switch read {
        case .read(let detail, let accountId):
            return .read(detail.pull, accountId: accountId)
        case .connectAccount:
            return .unread(.connectAccount(instanceId: link.instanceId))
        case .hidden(let error):
            let reference = "\(link.host.slug) \(link.host.provider.reference(link.number))"
            return .unread(.failed("\(reference) — \(PullRequestStore.message(for: error))"))
        case .failed(let error):
            return .unread(.failed(PullRequestStore.message(for: error)))
        case .noToken(let failure):
            return .unread(.failed(failure ?? String(localized: "Request failed")))
        }
    }

    /// What trying a read with each account in turn came to.
    private enum AccountRead<Value> {
        /// The first account that could, and what it read.
        case read(Value, accountId: UUID)
        /// None could, and connecting one may: one must be connected again,
        /// or there's none.
        case connectAccount
        /// None could see it: the first 404 or 403.
        case hidden(PullRequestFetchError)
        /// Another error stopped the reads.
        case failed(any Error)
        /// No account had a token, with the reason when one was given.
        case noToken(String?)
    }

    /// Runs `call` with the first of `accounts` that can (R2 Ruling 10): a
    /// 404 or a 403 moves on to the next account, a 401 renews the token and
    /// retries once, and any other error stops.
    private func readWithAccounts<Value>(_ accounts: [UUID],
                                         _ call: (String) async throws -> Value) async -> AccountRead<Value> {
        guard !accounts.isEmpty else { return .connectAccount }
        let tokens = TokenBook(ask: environment.token)
        var hidden: PullRequestFetchError?
        for accountId in accounts {
            await tokens.prepare(accountId)
            do {
                if let value = try await withToken(accountId, tokens, call) {
                    return .read(value, accountId: accountId)
                }
            } catch let error as PullRequestFetchError where error == .notFound || error == .forbidden {
                hidden = hidden ?? error
            } catch {
                return .failed(error)
            }
        }
        if !tokens.reconnect.isEmpty { return .connectAccount }
        if let hidden { return .hidden(hidden) }
        return .noToken(tokens.failure)
    }

    /// The accounts that may read a repo's pull requests from a link or a
    /// search (R2 Ruling 10): a followed repo's own; else its instance's,
    /// those that sign first with the owner's login at their head, then
    /// those to connect again.
    private func readAccounts(for host: RemoteHost, instanceId: UUID) -> [UUID] {
        if let repo = repos.first(where: { $0.id == FollowedRepos.key(host) }) { return [repo.accountId] }
        let onInstance = environment.accounts().filter { $0.instance.id == instanceId }.map(\.account)
        let signing = onInstance.filter { AccountGitCredentials.signs($0) }
        let rest = onInstance.filter { !AccountGitCredentials.signs($0) }
        return (FollowedRepos.accountsInPreference(for: host, among: signing) + rest).map(\.id)
    }

    /// The repo a link's pull request shows with (R2 Ruling 9): the followed
    /// one, else `looseRepo`.
    private func repoForLink(_ link: PullRequestLink, accountId: UUID) -> ReviewRepo {
        repos.first { $0.id == FollowedRepos.key(link.host) }
            ?? looseRepo(link.host, accountId: accountId, cloneURL: FollowedRepos.cloneURL(for: link.host))
    }

    /// A repo that isn't followed, as the Others and the browsed repos show
    /// it: read with `accountId`, cloned from its membership's URL when known
    /// (else `cloneURL`), and with the clone the last refresh saw.
    private func looseRepo(_ host: RemoteHost, accountId: UUID, cloneURL: String) -> ReviewRepo {
        let member = memberships[accountId]?.repos.first { $0.fullName.lowercased() == host.slug.lowercased() }
        return ReviewRepo(host: host, accountId: accountId, sources: [], lastActivity: nil,
                          cloneURL: member?.httpsURL ?? cloneURL, localURL: knownClones[FollowedRepos.key(host)])
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

    /// Opens `pendingLink` again, once, after the sheet to connect an account
    /// closes (R3 Ruling 14): only if its instance has an account that signs
    /// now; if not it's dropped, and the answer is `nil`. Opened again, a
    /// link that asks for an account once more isn't kept for another try.
    func retryPendingLink() async -> LinkOpenOutcome? {
        guard let link = pendingLink else { return nil }
        pendingLink = nil
        guard searchAccount(on: link.instanceId) != nil else { return nil }
        let outcome = await openLink(link)
        if case .connectAccount = outcome, pendingLink == link { pendingLink = nil }
        return outcome
    }

    // MARK: Search all and found repos

    /// Drops the searches that ended asking for an account, once the sheet to
    /// connect one closes: ⌘K offers to search those hosts again instead of
    /// the connect sheet. The other searches stay.
    func forgetConnectSearches() {
        let kept = hostSearches.filter { $0.value.phase != .connectAccount }
        if kept.count != hostSearches.count { hostSearches = kept }
    }

    /// Searches the whole of instance `instanceId` for `query`, trimmed (R3
    /// Ruling 12). Under `searchMinimum` characters, or on an instance with
    /// no account in the inbox, nothing is asked. `hostSearches` says it's
    /// searching, then what came of it (`searchPhase`). A newer search of the
    /// instance wins: an older one that lands later changes nothing.
    func searchHost(_ instanceId: UUID, query: String) async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= Self.searchMinimum,
              let instance = searchInstances.first(where: { $0.id == instanceId }) else { return }
        searchCounter &+= 1
        let gen = searchCounter
        latestSearch[instanceId] = gen
        hostSearches[instanceId] = HostSearchState(query: text, phase: .searching)
        let phase = await searchPhase(text, on: instance)
        guard latestSearch[instanceId] == gen else { return }
        hostSearches[instanceId] = HostSearchState(query: text, phase: phase)
    }

    /// What searching `instance` for `text` comes to, with its first account
    /// that signs (`searchAccount`); a 401 renews the token once. On
    /// github.com and gitlab.com the search keeps to the owners of the
    /// account's repos (`searchOwners`), from its membership list of any age,
    /// read now when there's none; if that read fails, so does the search.
    /// With a list that gives no owner to keep to, it finds nothing, without
    /// asking: unscoped, it would search the whole public site.
    private func searchPhase(_ text: String, on instance: HostingInstance) async -> HostSearchState.Phase {
        guard let account = searchAccount(on: instance.id) else { return .connectAccount }
        let tokens = TokenBook(ask: environment.token)
        await tokens.prepare(account.id)
        var owners: [String]?
        if instance.isBuiltIn, tokens.current(account.id) != nil {
            let members: [RemoteRepoSummary]
            if let list = memberships[account.id] {
                members = list.repos
            } else {
                do {
                    // No token left to read with (`nil`): the search below says why.
                    members = try await readMembership(of: account, on: instance, tokens: tokens,
                                                       now: environment.now())?.repos ?? []
                } catch {
                    return .failed(PullRequestStore.message(for: error))
                }
            }
            owners = Self.searchOwners(on: instance, members: members, login: account.login ?? logins[account.id])
        }
        let search = environment.makeSearch(instance.kind)
        do {
            if owners?.isEmpty == true, tokens.current(account.id) != nil { return .found(HostSearchResults()) }
            if let results = try await withToken(account.id, tokens, { token in
                try await Self.searchPullsAndRepos(text, owners: owners, on: instance, token: token, with: search)
            }) {
                return .found(results)
            }
        } catch {
            return .failed(PullRequestStore.message(for: error))
        }
        if tokens.reconnect.contains(account.id) { return .connectAccount }
        return .failed(tokens.failure ?? String(localized: "Request failed"))
    }

    /// Opens a repo found by searching a host (R3 Ruling 13). A followed one
    /// narrows the inbox to it at once (`showRepo`), reading nothing; it
    /// takes no turn from the links, so an `openLink` or `openFoundRepo`
    /// started before it that lands later may still select or narrow over
    /// it. Any other takes a turn, as `openLink` does (`linkGen`), and has
    /// its open pull requests read with the first account that can
    /// (`readWithAccounts`): each joins the Others, unless it's a row of the
    /// list already, the repo joins `browsedRepos`, in place of an older
    /// entry, and the inbox is narrowed to it. The section leaves a
    /// repository's list for the inbox as the read starts (U1 Ruling M), and
    /// doesn't go back to it if the read fails; narrowed, the list is set
    /// aside for the × of the filter, unless the tab was changed meanwhile.
    /// A later `openLink` or `openFoundRepo` that takes a turn wins over it:
    /// this one then lands adding its rows and its repo, but leaves the
    /// filter and the selection.
    func openFoundRepo(_ found: FoundRepo) async -> RepoOpenOutcome {
        let repoKey = FollowedRepos.key(found.host)
        if repos.contains(where: { $0.id == repoKey }) {
            showRepo(repoKey)
            return .shown(repoKey: repoKey)
        }
        linkGen &+= 1
        let gen = linkGen
        // The link being read gives way: its row still lands, unselected.
        if openingLink != nil { openingLink = nil }
        let leftList = leaveRepositoryList()
        let leftOn = tab
        let provider = environment.makeProvider(found.host)
        let read = await readWithAccounts(readAccounts(for: found.host, instanceId: found.instanceId)) { token in
            try await provider.fetchPulls(host: found.host, state: .open, token: token)
        }
        let pulls: [PullRequest]
        let accountId: UUID
        switch read {
        case .read(let list, let reader):
            (pulls, accountId) = (list, reader)
        case .connectAccount:
            return .connectAccount(instanceId: found.instanceId)
        case .hidden(let error):
            return .failed("\(found.host.slug) — \(PullRequestStore.message(for: error))")
        case .failed(let error):
            return .failed("\(found.host.slug) — \(PullRequestStore.message(for: error))")
        case .noToken(let failure):
            return .failed("\(found.host.slug) — \(failure ?? String(localized: "Request failed"))")
        }
        // A refresh may have run meanwhile: the repo and the list as they are now.
        let followed = repos.first { $0.id == repoKey }
        let repo = followed ?? looseRepo(found.host, accountId: accountId, cloneURL: found.cloneURL)
        for pull in pulls.sorted(by: Self.newerFirst) where !isListed(repoKey: repoKey, number: pull.number) {
            addOther(InboxPull(repo: repo, pull: pull), gen: gen)
        }
        if followed == nil { browsedRepos = browsedRepos.filter { $0.id != repoKey } + [repo] }
        if gen == linkGen { narrow(to: repoKey, leftList: tab == leftOn ? leftList : nil) }
        return .shown(repoKey: repoKey)
    }

    // MARK: Auto refresh

    /// Refreshes every `autoRefreshInterval` while `isOnline` and `isActive`
    /// hold (`autoRefreshOnce`). Replaces a loop already running.
    func startAutoRefresh(isOnline: @escaping @MainActor () -> Bool, isActive: @escaping @MainActor () -> Bool) {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.autoRefreshInterval)
                guard !Task.isCancelled, let self else { return }
                if isOnline(), isActive() { await self.autoRefreshOnce() }
            }
        }
    }

    /// One turn of the auto refresh: the inbox and, at the same time, the
    /// list of the repository open in gitForge while it isn't followed, which
    /// its group in Team and Mine shows (`visitingRepo`, U1 Ruling 3). A
    /// followed one's rows come with the inbox's own read. The open
    /// repository's list is re-read quietly: a timer never asks for an
    /// account nor reloads Closed (`refreshOpenListQuietly`).
    func autoRefreshOnce() async {
        let visiting = visitingRepo == nil ? nil : activeRepository?.store
        async let inbox: Void = refresh(force: true)
        async let repository: Void? = visiting?.refreshOpenListQuietly()
        _ = await (inbox, repository)
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }
}
