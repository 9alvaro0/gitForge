import Foundation
import Testing
@testable import gitForge

/// A value behind a lock: the fakes are called from several reads at once.
private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func callAsFunction<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        try lock.withLock { try body(&value) }
    }
}

/// Scripted host: open lists and failures by `owner/repo`, tokens it
/// rejects, and a log of what was read.
private final class FakeProvider: PullRequestProvider, PullRequestReviewProvider, Sendable {
    struct State {
        var lists: [String: [PullRequest]] = [:]
        var failures: [String: PullRequestFetchError] = [:]
        var failEverything: PullRequestFetchError?
        var rejecting: Set<String> = []
        var delay: Duration = .zero
        var user = "marta"
        /// The `owner/repo` of each list read.
        var reads: [String] = []
        var running = 0
        var mostRunning = 0
        var userReads = 0
    }

    let state = Locked(State())

    func fetchPulls(host: RemoteHost, state list: PullListState, token: String) async throws -> [PullRequest] {
        let delay = state { state in
            state.running += 1
            state.mostRunning = max(state.mostRunning, state.running)
            return state.delay
        }
        defer { state { $0.running -= 1 } }
        if delay > .zero { try await Task.sleep(for: delay) }
        return try state { state in
            state.reads.append(host.slug)
            if state.rejecting.contains(token) { throw PullRequestFetchError.unauthorized }
            if let error = state.failEverything ?? state.failures[host.slug] { throw error }
            return state.lists[host.slug] ?? []
        }
    }
    func fetchCurrentUser(host: RemoteHost, token: String) async throws -> String {
        state { state in
            state.userReads += 1
            return state.user
        }
    }
    func fetchChecks(host: RemoteHost, pull: PullRequest, token: String) async throws -> [CICheck] { [] }
    func fetchCommitChecks(host: RemoteHost, sha: String, token: String) async throws -> [CICheck] { [] }
    func fetchDetail(host: RemoteHost, number: Int, token: String) async throws -> PullRequestDetail {
        guard let pull = state({ $0.lists[host.slug]?.first { $0.number == number } }) else {
            throw PullRequestFetchError.notFound
        }
        return PullRequestDetail(pull: pull, descriptionMarkdown: nil, labels: [], reviewers: [], assignees: [],
                                 mergeable: true, ciStatus: nil)
    }
    func fetchCommits(host: RemoteHost, number: Int, token: String) async throws -> [PullRequestCommit] { [] }
    func fetchFiles(host: RemoteHost, number: Int, token: String) async throws -> [PullRequestFileChange] { [] }

    // The detail store's writes: nothing to write in these tests.
    func requestChangesSupport(host: RemoteHost, token: String) async -> RequestChangesSupport { .supported }
    func submitReview(host: RemoteHost, pull: PullRequest, verdict: ReviewVerdict,
                      body: String, token: String) async throws -> String? { nil }
    func fetchMergeOptions(host: RemoteHost, pull: PullRequest, detail: PullRequestDetail,
                           commits: [PullRequestCommit], token: String) async throws -> MergeOptions {
        throw PullRequestFetchError.notFound
    }
    func merge(host: RemoteHost, pull: PullRequest, input: MergeInput, token: String) async throws -> MergeOutcome {
        throw PullRequestFetchError.notFound
    }
    func fetchThreads(host: RemoteHost, pull: PullRequest, detail: PullRequestDetail?,
                      token: String) async throws -> [ReviewThread] { [] }
    func addComment(host: RemoteHost, pull: PullRequest, detail: PullRequestDetail?, target: CommentTarget,
                    body: String, token: String) async throws {}
    func reply(host: RemoteHost, pull: PullRequest, thread: ReviewThread, body: String, token: String) async throws {}
    func setResolved(_ resolved: Bool, host: RemoteHost, pull: PullRequest, thread: ReviewThread,
                     token: String) async throws {}
}

/// The account's repos on one page, then an empty one.
private final class FakeBrowser: RemoteRepoBrowsing, Sendable {
    struct State {
        var members: [RemoteRepoSummary] = []
        var failure: PullRequestFetchError?
        /// Reads of the first page: one per membership listing.
        var listings = 0
    }

    let state = Locked(State())

    func fetchUserRepos(apiBase: URL, token: String, page: Int) async throws -> [RemoteRepoSummary] {
        try state { state in
            if page == 1 { state.listings += 1 }
            if let failure = state.failure { throw failure }
            return page == 1 ? state.members : []
        }
    }
}

/// Fixed hits, and the login each read was made with.
private final class FakeActivity: ReviewActivitySource, Sendable {
    struct State {
        var hits: [ActivityHit] = []
        var failure: PullRequestFetchError?
        var logins: [String] = []
    }

    let state = Locked(State())

    func recentActivity(apiBase: URL, login: String, since: Date, token: String) async throws -> [ActivityHit] {
        try state { state in
            state.logins.append(login)
            if let failure = state.failure { throw failure }
            return state.hits
        }
    }
}

/// Accounts on `gitlab.example.test`, their clones, the fakes, the clock
/// and the snapshot folder; `makeStore` builds a store on them, as a launch.
@MainActor
private final class Harness {
    static let instance = HostingInstance(kind: .gitlab, host: "gitlab.example.test")

    /// In store order.
    var accounts: [HostingAccount]
    let provider = FakeProvider()
    let browser = FakeBrowser()
    let activity = FakeActivity()
    var locals: [LocalRemote] = []
    /// Holds `localRemotes` until opened, when set.
    var localsGate: AsyncGate?
    /// Calls to `localRemotes`.
    private(set) var localReads = 0
    var now = Harness.date(1_790_000_000)
    /// The token an account that signs gives; its argument is the rejected one, if any.
    var answer: (String?) -> PullRequestAuthResult = { _ in .token("t") }
    /// The tokens the store asked to renew.
    private(set) var renewals: [String] = []
    let directory = TemporaryDirectories.make("gitForge-reviews-store")

    init(login: String? = "marta") {
        accounts = [HostingAccount(instanceId: Self.instance.id, login: login, method: .oauth, status: .ok)]
    }

    /// The first account.
    var account: HostingAccount {
        get { accounts[0] }
        set { accounts[0] = newValue }
    }

    func makeStore() -> ReviewsStore {
        ReviewsStore(environment: ReviewsEnvironment(
            accounts: { [self] in accounts.map { (account: $0, instance: Self.instance) } },
            localRemotes: { [self] in
                localReads += 1
                if let localsGate { await localsGate.wait() }
                return locals
            },
            token: { [self] accountId, rejected in
                // As `AccountPullRequestAuth.access(accountId:)`: an account
                // that doesn't sign has to be connected again.
                if let account = accounts.first(where: { $0.id == accountId }), !AccountGitCredentials.signs(account) {
                    return .connectAccount(instanceId: Self.instance.id, replacing: accountId)
                }
                if let rejected { renewals.append(rejected) }
                return answer(rejected)
            },
            makeProvider: { [provider] _ in provider },
            makeBrowser: { [browser] _ in browser },
            makeActivity: { [activity] _ in activity },
            snapshots: ReviewsSnapshotStore(directory: directory),
            now: { [self] in now },
            makeReviewProvider: { [provider] _ in provider }))
    }

    static func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

    static func host(_ path: String) -> RemoteHost { RemoteHost.make(fullName: path, on: instance)! }

    static func key(_ path: String) -> String { FollowedRepos.key(host(path)) }

    /// A clone of `path`; `account` is the one its own Pull requests screen reads it with, if any.
    static func local(_ path: String, account: UUID? = nil) -> LocalRemote {
        LocalRemote(host: host(path), repository: Repository(url: URL(fileURLWithPath: "/r/\(path)"),
                                                            lastOpenedAt: date(1_780_000_000)),
                    assignedAccountId: account)
    }

    static func member(_ id: String, _ path: String) -> RemoteRepoSummary {
        RemoteRepoSummary(id: id, name: String(path.split(separator: "/").last ?? ""), fullName: path,
                          description: nil, sshURL: nil, httpsURL: "https://gitlab.example.test/\(path).git",
                          isPrivate: true, defaultBranch: "main")
    }

    static func pr(_ number: Int, by author: String, state: PullRequest.State = .open,
                   updated: TimeInterval) -> PullRequest {
        PullRequest(id: "iid:\(number)", number: number, title: "MR \(number)", state: state, authorLogin: author,
                    authorAvatarURL: nil, sourceBranch: "feature/\(number)", targetBranch: "main", webURL: nil,
                    createdAt: date(updated), updatedAt: date(updated), headSha: nil)
    }
}

@Suite("Reviews store")
@MainActor
struct ReviewsStoreTests {
    /// A clone of team/app, and recent activity in team/api, a repo the
    /// account belongs to.
    private static func twoRepos(login: String? = "marta") -> Harness {
        let harness = Harness(login: login)
        harness.locals = [Harness.local("team/app")]
        harness.browser.state { $0.members = [Harness.member("2", "team/api")] }
        harness.activity.state { $0.hits = [ActivityHit(ref: .projectId("2"), at: Harness.date(1_789_000_000))] }
        return harness
    }

    private static func reads(_ harness: Harness) -> Int { harness.provider.state { $0.reads.count } }

    @Test("Groups follow their newest update, and Team and Mine split the pull requests by author")
    func groupsAndFilters() async {
        let harness = Self.twoRepos()
        harness.provider.state {
            $0.lists["team/app"] = [Harness.pr(1, by: "octo", updated: 100), Harness.pr(2, by: "marta", updated: 300)]
            $0.lists["team/api"] = [Harness.pr(3, by: "octo", updated: 200),
                                    Harness.pr(4, by: "octo", state: .draft, updated: 150),
                                    Harness.pr(5, by: "marta", state: .draft, updated: 50)]
        }
        let store = harness.makeStore()
        await store.refresh(force: true)

        #expect(store.repos.first { $0.host.repo == "app" }?.sources == [.local])
        #expect(store.repos.first { $0.host.repo == "api" }?.sources == [.activity])
        #expect(store.filter == .team)
        #expect(store.groups.map(\.repo.host.repo) == ["api", "app"])
        #expect(store.groups.map { $0.pulls.map(\.pull.number) } == [[3, 4], [1]])
        #expect(store.groups.first?.pulls.first?.id == "gitlab.example.test/team/api#3")
        #expect(store.groups.allSatisfy { $0.error == nil })

        store.filter = .mine
        #expect(store.groups.map(\.repo.host.repo) == ["app", "api"])
        #expect(store.groups.map { $0.pulls.map(\.pull.number) } == [[2], [5]])
    }

    @Test("The count is the open pull requests of others: no drafts, and the login matches in any case")
    func badge() async {
        let harness = Harness(login: "Marta")
        harness.locals = [Harness.local("team/app")]
        harness.provider.state {
            $0.lists["team/app"] = [Harness.pr(1, by: "octo", updated: 1), Harness.pr(2, by: "lucia", updated: 2),
                                    Harness.pr(3, by: "octo", updated: 3),
                                    Harness.pr(4, by: "octo", state: .draft, updated: 4),
                                    Harness.pr(5, by: "marta", updated: 5)]
        }
        let store = harness.makeStore()
        await store.refresh(force: true)

        #expect(store.badgeCount == 3)
        store.filter = .mine
        #expect(store.groups.map { $0.pulls.map(\.pull.number) } == [[5]])
    }

    @Test("A repo that answers 404 loses its pull requests and shows why, last; the other loads")
    func partialErrors() async {
        let harness = Self.twoRepos()
        harness.provider.state {
            $0.lists["team/app"] = [Harness.pr(1, by: "octo", updated: 100)]
            $0.lists["team/api"] = [Harness.pr(2, by: "octo", updated: 200)]
        }
        let store = harness.makeStore()
        await store.refresh(force: true)
        #expect(store.badgeCount == 2)

        harness.provider.state { $0.failures["team/api"] = .notFound }
        await store.refresh(force: true)

        let api = Harness.key("team/api")
        #expect(store.pulls[api] == nil)
        #expect(store.repoErrors[api] == PullRequestStore.message(for: PullRequestFetchError.notFound))
        #expect(store.pulls[Harness.key("team/app")]?.map(\.number) == [1])
        #expect(store.groups.map(\.repo.host.repo) == ["app", "api"])
        #expect(store.groups.last?.pulls.isEmpty == true)
        #expect(store.groups.last?.error == store.repoErrors[api])
        #expect(store.badgeCount == 1)
        #expect(!store.lastRefreshFailed)
    }

    @Test("A server that's down or busy keeps the repo's pull requests, without an error", arguments: [500, 502, 503, 429])
    func transientServerError(code: Int) async {
        let harness = Harness()
        harness.locals = [Harness.local("team/app")]
        harness.provider.state { $0.lists["team/app"] = [Harness.pr(1, by: "octo", updated: 100)] }
        let store = harness.makeStore()
        await store.refresh(force: true)

        harness.provider.state { $0.failures["team/app"] = .server(code, "Service Unavailable") }
        await store.refresh(force: true)

        #expect(store.pulls[Harness.key("team/app")]?.map(\.number) == [1])
        #expect(store.repoErrors.isEmpty)
        #expect(store.badgeCount == 1)
    }

    @Test("Any other server error still drops the repo's pull requests and says why")
    func otherServerError() async {
        let harness = Harness()
        harness.locals = [Harness.local("team/app")]
        harness.provider.state { $0.lists["team/app"] = [Harness.pr(1, by: "octo", updated: 100)] }
        let store = harness.makeStore()
        await store.refresh(force: true)

        let error = PullRequestFetchError.server(422, "Unprocessable")
        harness.provider.state { $0.failures["team/app"] = error }
        await store.refresh(force: true)

        #expect(store.pulls[Harness.key("team/app")] == nil)
        #expect(store.repoErrors[Harness.key("team/app")] == PullRequestStore.message(for: error))
    }

    @Test("Offline, a refresh keeps the snapshot's pull requests and its date, and says it failed")
    func offlineKeepsSnapshot() async {
        let harness = Self.twoRepos()
        harness.provider.state {
            $0.lists["team/app"] = [Harness.pr(1, by: "octo", updated: 100)]
            $0.lists["team/api"] = [Harness.pr(2, by: "octo", updated: 200)]
        }
        await harness.makeStore().refresh(force: true)
        let savedAt = harness.now

        // The next launch, a day later (the membership is due again) and offline.
        harness.now = savedAt.addingTimeInterval(25 * 3600)
        let offline = PullRequestFetchError.network("The Internet connection appears to be offline.")
        harness.browser.state { $0.failure = offline }
        harness.activity.state { $0.failure = offline }
        harness.provider.state { $0.failEverything = offline }
        let store = harness.makeStore()
        store.loadSnapshot()
        #expect(store.lastRefreshedAt == savedAt)
        await store.refresh(force: true)

        #expect(store.groups.flatMap(\.pulls).map(\.pull.number).sorted() == [1, 2])
        #expect(store.lastRefreshFailed)
        #expect(store.lastRefreshedAt == savedAt)
        #expect(store.repoErrors.isEmpty)
        let onDisk = ReviewsSnapshotStore(directory: harness.directory).load()
        #expect(onDisk?.pulls.values.flatMap { $0 }.count == 2)
        #expect(onDisk?.savedAt == savedAt)
    }

    @Test("A rejected token is renewed once and the reads retried; an account to reconnect keeps its pull requests")
    func expiredToken() async {
        let harness = Self.twoRepos()
        harness.provider.state {
            $0.lists["team/app"] = [Harness.pr(1, by: "octo", updated: 100)]
            $0.lists["team/api"] = [Harness.pr(2, by: "octo", updated: 200)]
            $0.rejecting = ["old"]
        }
        harness.answer = { rejected in .token(rejected == nil ? "old" : "new") }
        let store = harness.makeStore()
        await store.refresh(force: true)

        #expect(harness.renewals == ["old"])
        #expect(store.badgeCount == 2)
        #expect(store.accountsNeedingAttention.isEmpty)

        // This time the renewal fails: the account has to be connected again.
        let accountId = harness.account.id
        harness.provider.state { $0.rejecting = ["stale"] }
        harness.answer = { rejected in
            rejected == nil ? .token("stale") : .connectAccount(instanceId: Harness.instance.id, replacing: accountId)
        }
        await store.refresh(force: true)

        #expect(harness.renewals == ["old", "stale"])
        #expect(store.accountsNeedingAttention == [accountId])
        #expect(store.badgeCount == 2)
        #expect(store.repoErrors.isEmpty)

        // Connected again.
        harness.provider.state { $0.rejecting = [] }
        harness.answer = { _ in .token("fresh") }
        await store.refresh(force: true)
        #expect(store.accountsNeedingAttention.isEmpty)
    }

    @Test("The membership is read once a day")
    func membershipCached() async {
        let harness = Self.twoRepos()
        let store = harness.makeStore()
        await store.refresh(force: true)
        await store.refresh(force: true)
        #expect(harness.browser.state { $0.listings } == 1)
        #expect(store.repos.count == 2)

        harness.now = harness.now.addingTimeInterval(25 * 3600)
        await store.refresh(force: true)
        #expect(harness.browser.state { $0.listings } == 2)
        #expect(store.repos.count == 2)
    }

    @Test("Two refreshes in a row read the pull requests once, unless forced")
    func throttle() async {
        let harness = Harness()
        harness.locals = [Harness.local("team/app")]
        let store = harness.makeStore()
        await store.refresh()
        await store.refresh()
        #expect(Self.reads(harness) == 1)

        await store.refresh(force: true)
        #expect(Self.reads(harness) == 2)

        harness.now = harness.now.addingTimeInterval(ReviewsStore.reloadThrottle)
        await store.refresh()
        #expect(Self.reads(harness) == 3)
    }

    @Test("While a read runs with nothing to show, the list shows the loading placeholder, even after an earlier read")
    func loadingPlaceholder() async {
        let harness = Harness()
        harness.locals = [Harness.local("team/app")]
        let store = harness.makeStore()
        // An earlier read found nothing: the inbox has a date and no groups.
        await store.refresh(force: true)
        #expect(store.lastRefreshedAt != nil)
        #expect(store.listContent == .empty)

        // The next one (say, the first after connecting an account) is still reading.
        let reading = AsyncGate()
        harness.localsGate = reading
        harness.provider.state { $0.lists["team/app"] = [Harness.pr(1, by: "octo", updated: 1)] }
        let round = Task { await store.refresh(force: true) }
        await reading.waiting()
        #expect(store.listContent == .loading)
        reading.open()
        await round.value
        #expect(store.listContent == .groups(store.groups))
        #expect(store.groups.count == 1)

        // With rows to show, a read doesn't hide them.
        let again = AsyncGate()
        harness.localsGate = again
        let next = Task { await store.refresh(force: true) }
        await again.waiting()
        #expect(store.listContent == .groups(store.groups))
        again.open()
        await next.value
    }

    @Test("Without accounts a refresh reads no clones and writes nothing, and doesn't hold back the first with one")
    func noAccounts() async {
        let harness = Harness()
        let account = harness.account
        harness.accounts = []
        harness.locals = [Harness.local("team/app")]
        harness.provider.state { $0.lists["team/app"] = [Harness.pr(1, by: "octo", updated: 1)] }
        let store = harness.makeStore()
        await store.refresh(force: true)
        await store.refresh(force: true)

        #expect(harness.localReads == 0)
        #expect(Self.reads(harness) == 0)
        #expect(ReviewsSnapshotStore(directory: harness.directory).load() == nil)
        #expect(store.repos.isEmpty)

        // An account is connected right after: the next refresh reads, throttle or not.
        harness.accounts = [account]
        await store.refresh()
        #expect(harness.localReads == 1)
        #expect(store.badgeCount == 1)
    }

    @Test("When the last account goes, a refresh empties the inbox and saves it once")
    func lastAccountRemoved() async throws {
        let harness = Self.twoRepos()
        harness.provider.state {
            $0.lists["team/app"] = [Harness.pr(1, by: "octo", updated: 100)]
            $0.lists["team/api"] = [Harness.pr(2, by: "octo", updated: 200)]
        }
        let store = harness.makeStore()
        await store.refresh(force: true)
        let item = try #require(store.groups.first?.pulls.first)
        store.selectedID = item.id
        #expect(store.detailStore(for: item.repo.id) != nil)
        let localReads = harness.localReads

        harness.accounts = []
        await store.refresh(force: true)

        #expect(harness.localReads == localReads)
        #expect(store.repos.isEmpty)
        #expect(store.pulls.isEmpty)
        #expect(store.repoErrors.isEmpty)
        #expect(store.logins.isEmpty)
        #expect(store.selectedID == nil)
        #expect(store.badgeCount == 0)
        #expect(store.detailStore(for: item.repo.id) == nil)
        let onDisk = ReviewsSnapshotStore(directory: harness.directory).load()
        #expect(onDisk?.repos.isEmpty == true)
        #expect(onDisk?.pulls.isEmpty == true)

        // Nothing left to clear: the next refreshes write nothing.
        try FileManager.default.removeItem(at: harness.directory.appendingPathComponent("reviews.json"))
        await store.refresh(force: true)
        await store.refresh(force: true)
        #expect(ReviewsSnapshotStore(directory: harness.directory).load() == nil)
        #expect(harness.localReads == localReads)
    }

    @Test("Reloading a repo after a merge drops the merged pull request and lowers the count")
    func reloadAfterMerge() async {
        let harness = Harness()
        harness.locals = [Harness.local("team/app")]
        harness.provider.state {
            $0.lists["team/app"] = [Harness.pr(1, by: "octo", updated: 100), Harness.pr(2, by: "octo", updated: 200)]
        }
        let store = harness.makeStore()
        await store.refresh(force: true)
        #expect(store.badgeCount == 2)

        harness.provider.state { $0.lists["team/app"] = [Harness.pr(2, by: "octo", updated: 200)] }
        await store.reload(repoKey: Harness.key("team/app"))

        #expect(store.groups.flatMap(\.pulls).map(\.pull.number) == [2])
        #expect(store.badgeCount == 1)
        let onDisk = ReviewsSnapshotStore(directory: harness.directory).load()
        #expect(onDisk?.pulls[Harness.key("team/app")]?.map(\.number) == [2])
    }

    @Test("A new store shows the last snapshot's groups before reading anything")
    func snapshotOnLaunch() async {
        let harness = Self.twoRepos()
        harness.provider.state {
            $0.lists["team/app"] = [Harness.pr(1, by: "octo", updated: 100), Harness.pr(2, by: "marta", updated: 300)]
            $0.lists["team/api"] = [Harness.pr(3, by: "octo", updated: 200)]
        }
        let first = harness.makeStore()
        await first.refresh(force: true)
        let reads = Self.reads(harness)

        let next = harness.makeStore()
        next.loadSnapshot()

        #expect(next.groups.count == 2)
        #expect(next.groups == first.groups)
        #expect(next.badgeCount == 2)
        #expect(next.lastRefreshedAt == harness.now)
        next.filter = .mine
        #expect(next.groups.map { $0.pulls.map(\.pull.number) } == [[2]])
        #expect(Self.reads(harness) == reads)
        #expect(harness.browser.state { $0.listings } == 1)
    }

    @Test("Opening a pull request selects it in its repo's detail store, which loads it and is reused")
    func openDetail() async {
        let harness = Harness()
        harness.locals = [Harness.local("team/app")]
        harness.provider.state {
            $0.lists["team/app"] = [Harness.pr(1, by: "octo", updated: 100), Harness.pr(2, by: "octo", updated: 200)]
        }
        let store = harness.makeStore()
        await store.refresh(force: true)
        guard let first = store.groups.first?.pulls.first, let second = store.groups.first?.pulls.last,
              first.id != second.id else {
            Issue.record("Expected two rows in team/app")
            return
        }

        await store.open(first)
        let detail = store.detailStore(for: first.repo.id)
        #expect(detail?.selected?.number == first.pull.number)
        await waitUntil { detail?.detail != nil && detail?.isLoadingDetail == false }
        #expect(detail?.detail?.pull.number == first.pull.number)
        #expect(detail?.detailError == nil)

        await store.open(second)
        #expect(store.detailStore(for: second.repo.id) === detail)
        #expect(detail?.selected?.number == second.pull.number)
    }

    @Test("At most six lists are read at once, and every repo is read")
    func concurrencyLimit() async {
        let harness = Harness()
        harness.locals = (0..<10).map { Harness.local("team/repo\($0)") }
        harness.provider.state { state in
            state.delay = .milliseconds(20)
            for index in 0..<10 { state.lists["team/repo\(index)"] = [Harness.pr(index + 1, by: "octo", updated: 1)] }
        }
        let store = harness.makeStore()
        await store.refresh(force: true)

        #expect(harness.provider.state { $0.mostRunning } <= ReviewsStore.concurrency)
        #expect(Self.reads(harness) == 10)
        #expect(store.badgeCount == 10)
    }

    @Test("A refresh cancelled while it reads the clones commits nothing, in memory or on disk")
    func cancelledRefreshCommitsNothing() async {
        let harness = Self.twoRepos()
        harness.provider.state {
            $0.lists["team/app"] = [Harness.pr(1, by: "octo", updated: 100)]
            $0.lists["team/api"] = [Harness.pr(2, by: "octo", updated: 200)]
        }
        let store = harness.makeStore()
        await store.refresh(force: true)
        let repos = store.repos
        let pulls = store.pulls
        let refreshedAt = store.lastRefreshedAt
        let onDisk = ReviewsSnapshotStore(directory: harness.directory).load()
        let reads = Self.reads(harness)
        #expect(onDisk != nil)

        // Cancelled, `GitCLI` reads no `origin`: the clones come back empty.
        let gate = AsyncGate()
        harness.localsGate = gate
        harness.locals = []
        harness.now = harness.now.addingTimeInterval(60)
        let round = Task { await store.refresh(force: true) }
        await gate.waiting()
        round.cancel()
        gate.open()
        await round.value

        #expect(store.repos == repos)
        #expect(store.pulls == pulls)
        #expect(store.lastRefreshedAt == refreshedAt)
        #expect(!store.isRefreshing)
        #expect(Self.reads(harness) == reads)
        #expect(ReviewsSnapshotStore(directory: harness.directory).load() == onDisk)

        // The cancelled round didn't count for the throttle.
        harness.localsGate = nil
        harness.locals = [Harness.local("team/app")]
        harness.now = harness.now.addingTimeInterval(10)
        await store.refresh()
        #expect(Self.reads(harness) == reads + 2)
    }

    @Test("An account that needs attention keeps its repos and pull requests across refreshes, flagged")
    func needsAttentionKeepsRepos() async {
        let harness = Self.twoRepos()
        harness.provider.state {
            $0.lists["team/app"] = [Harness.pr(1, by: "octo", updated: 100)]
            $0.lists["team/api"] = [Harness.pr(2, by: "octo", updated: 200)]
        }
        let store = harness.makeStore()
        await store.refresh(force: true)
        let refreshedAt = store.lastRefreshedAt

        // Its token was rejected meanwhile, and the account store marked it.
        harness.account.status = .needsAttention(.revoked)
        for _ in 0..<2 {
            harness.now = harness.now.addingTimeInterval(60)
            await store.refresh(force: true)
            #expect(store.repos.map(\.host.repo).sorted() == ["api", "app"])
            #expect(store.groups.flatMap(\.pulls).map(\.pull.number).sorted() == [1, 2])
            #expect(store.accountsNeedingAttention == [harness.account.id])
        }
        // Nothing was read: the pull requests are as old as before.
        #expect(store.lastRefreshedAt == refreshedAt)
        let onDisk = ReviewsSnapshotStore(directory: harness.directory).load()
        #expect(onDisk?.pulls.values.flatMap { $0 }.count == 2)
    }

    @Test("A repo with no assignment and no owner's login goes to the usable account, not a dead one before it")
    func usableAccountFirst() async {
        let harness = Harness()
        let usable = harness.account
        let dead = HostingAccount(instanceId: Harness.instance.id, login: "octo", method: .oauth,
                                  status: .needsAttention(.expired))
        harness.accounts = [dead, usable]
        harness.locals = [Harness.local("team/app")]
        harness.provider.state { $0.lists["team/app"] = [Harness.pr(1, by: "lucia", updated: 1)] }
        let store = harness.makeStore()
        await store.refresh(force: true)

        #expect(store.repos.map(\.accountId) == [usable.id])
        #expect(store.badgeCount == 1)
        #expect(store.accountsNeedingAttention == [dead.id])
    }

    @Test("Without a stored login, the login is read once per session and drives the activity")
    func loginLookedUpOnce() async {
        let harness = Self.twoRepos(login: nil)
        harness.provider.state {
            $0.user = "marta"
            $0.lists["team/api"] = [Harness.pr(1, by: "marta", updated: 1), Harness.pr(2, by: "octo", updated: 2)]
        }
        let store = harness.makeStore()
        await store.refresh(force: true)
        await store.refresh(force: true)

        #expect(harness.provider.state { $0.userReads } == 1)
        #expect(harness.activity.state { $0.logins } == ["marta", "marta"])
        #expect(store.logins[harness.account.id] == "marta")
        #expect(store.repos.contains { $0.host.repo == "api" })
        #expect(store.badgeCount == 1)
    }

    // MARK: Selection

    @Test("A selection the filter still shows stays; one it hides, or that left, goes without another taking its place")
    func selectionHygiene() async {
        let harness = Self.twoRepos()
        harness.provider.state {
            $0.lists["team/app"] = [Harness.pr(1, by: "octo", updated: 100), Harness.pr(2, by: "marta", updated: 300)]
            $0.lists["team/api"] = [Harness.pr(3, by: "octo", updated: 200),
                                    Harness.pr(4, by: "octo", state: .draft, updated: 150)]
        }
        let store = harness.makeStore()
        await store.refresh(force: true)
        let three = "gitlab.example.test/team/api#3"

        store.selectedID = three
        #expect(store.selectedItem?.pull.number == 3)
        store.dropHiddenSelection()
        #expect(store.selectedID == three)

        // Mine doesn't show it: nothing is selected, not the first of Mine.
        store.filter = .mine
        #expect(store.selectedItem == nil)
        store.dropHiddenSelection()
        #expect(store.selectedID == nil)

        // Back in Team, a pull request that leaves with a reload goes too.
        store.filter = .team
        store.selectedID = three
        harness.provider.state { $0.lists["team/api"] = [Harness.pr(4, by: "octo", state: .draft, updated: 150)] }
        await store.reload(repoKey: Harness.key("team/api"))
        #expect(store.selectedItem == nil)
        store.dropHiddenSelection()
        #expect(store.selectedID == nil)
    }

    @Test("The accounts to reconnect come with their instance; the ones that sign don't")
    func accountsToReconnect() async {
        let harness = Self.twoRepos()
        let dead = HostingAccount(instanceId: Harness.instance.id, login: "octo", method: .oauth,
                                  status: .needsAttention(.revoked))
        harness.accounts.append(dead)
        // The clone of team/app is read with the dead account: its repo stays listed.
        harness.locals = [Harness.local("team/app", account: dead.id)]
        let store = harness.makeStore()
        #expect(store.accountsToReconnect.isEmpty)

        await store.refresh(force: true)

        #expect(store.repos.first { $0.host.repo == "app" }?.accountId == dead.id)
        #expect(store.accountsToReconnect.map(\.account.id) == [dead.id])
        #expect(store.accountsToReconnect.map(\.instance.id) == [Harness.instance.id])
        // Removed meanwhile: no notice for an account that's gone.
        harness.accounts.removeLast()
        #expect(store.accountsToReconnect.isEmpty)
    }

    @Test("A dead account that owns no followed repo needs attention but gets no reconnect notice")
    func deadAccountWithoutReposHasNoNotice() async {
        let harness = Self.twoRepos()
        let dead = HostingAccount(instanceId: Harness.instance.id, login: "octo", method: .oauth,
                                  status: .needsAttention(.revoked))
        harness.accounts.append(dead)
        let store = harness.makeStore()

        await store.refresh(force: true)

        #expect(store.accountsNeedingAttention == [dead.id])
        #expect(store.repos.map(\.host.repo).sorted() == ["api", "app"])
        #expect(store.repos.allSatisfy { $0.accountId != dead.id })
        #expect(store.accountsToReconnect.isEmpty)
    }

    @Test("An account that goes dead keeps its notice while its repos stay, until it's connected again")
    func carriedOverReposKeepTheNotice() async {
        let harness = Self.twoRepos()
        harness.provider.state {
            $0.lists["team/app"] = [Harness.pr(1, by: "octo", updated: 100)]
            $0.lists["team/api"] = [Harness.pr(2, by: "octo", updated: 200)]
        }
        let store = harness.makeStore()
        await store.refresh(force: true)
        #expect(store.accountsToReconnect.isEmpty)

        // Its token was rejected meanwhile: both repos (a clone and a carried-over activity one) stay.
        harness.account.status = .needsAttention(.revoked)
        harness.now = harness.now.addingTimeInterval(60)
        await store.refresh(force: true)
        #expect(store.repos.count == 2)
        #expect(store.accountsToReconnect.map(\.account.id) == [harness.account.id])

        // Connected again.
        harness.account.status = .ok
        harness.now = harness.now.addingTimeInterval(60)
        await store.refresh(force: true)
        #expect(store.accountsNeedingAttention.isEmpty)
        #expect(store.accountsToReconnect.isEmpty)
    }
}

@Suite("Reviews inbox — detail")
struct ReviewsDetailRulesTests {
    private static func repo(localURL: URL?) -> ReviewRepo {
        ReviewRepo(host: RemoteHost(provider: .gitlab, host: "gitlab.example.test", owner: "apps/payments", repo: "ledger"),
                   accountId: UUID(), sources: [.activity], lastActivity: nil,
                   cloneURL: "https://gitlab.example.test/apps/payments/ledger.git", localURL: localURL)
    }

    @Test("A repo that isn't on this Mac offers to clone it with its clone URL; a clone, to open it")
    func repoAction() {
        #expect(ReviewRepoAction(Self.repo(localURL: nil)) == .clone(url: "https://gitlab.example.test/apps/payments/ledger.git"))
        let clone = URL(fileURLWithPath: "/Users/marta/Developer/ledger")
        #expect(ReviewRepoAction(Self.repo(localURL: clone)) == .openInRepository(clone))
    }

    @Test("Only the same pull request leaving open or draft, with its merge over, reloads its repo")
    func leftOpen() {
        func state(_ id: String, _ state: PullRequest.State, merging: Bool = false) -> ReviewDetailState {
            ReviewDetailState(itemID: id, state: state, isMerging: merging)
        }
        #expect(ReviewDetailState.leftOpen(from: state("a#1", .open), to: state("a#1", .merged)))
        #expect(ReviewDetailState.leftOpen(from: state("a#1", .draft), to: state("a#1", .closed)))
        // The merge sheet is still reading the result back.
        #expect(!ReviewDetailState.leftOpen(from: state("a#1", .open), to: state("a#1", .merged, merging: true)))
        #expect(ReviewDetailState.leftOpen(from: state("a#1", .merged, merging: true), to: state("a#1", .merged)))
        // Another pull request, or none.
        #expect(!ReviewDetailState.leftOpen(from: state("a#1", .open), to: state("b#2", .merged)))
        #expect(!ReviewDetailState.leftOpen(from: state("a#1", .open), to: nil))
        #expect(!ReviewDetailState.leftOpen(from: nil, to: state("a#1", .merged)))
        #expect(!ReviewDetailState.leftOpen(from: state("a#1", .open), to: state("a#1", .draft)))
    }
}
