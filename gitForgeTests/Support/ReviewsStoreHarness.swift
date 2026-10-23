import Foundation
@testable import gitForge

/// A value behind a lock: the fakes are called from several reads at once.
final class ReviewsLocked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func callAsFunction<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        try lock.withLock { try body(&value) }
    }
}

/// Scripted host: open lists and failures by `owner/repo`, tokens it
/// rejects, detail reads that fail by token or wait on a gate, and a log of
/// what was read.
final class ReviewsFakeProvider: PullRequestProvider, PullRequestReviewProvider, Sendable {
    struct State {
        var lists: [String: [PullRequest]] = [:]
        var failures: [String: PullRequestFetchError] = [:]
        var failEverything: PullRequestFetchError?
        var rejecting: Set<String> = []
        var delay: Duration = .zero
        /// Holds the list read of an `owner/repo` until its gate opens.
        var gates: [String: AsyncGate] = [:]
        var user = "marta"
        /// The `owner/repo` of each list read.
        var reads: [String] = []
        var running = 0
        var mostRunning = 0
        var userReads = 0
        /// What a detail read with a token throws, by token.
        var detailFailures: [String: PullRequestFetchError] = [:]
        /// Holds the detail read of a number until its gate opens.
        var detailGates: [Int: AsyncGate] = [:]
        /// Calls to `fetchDetail`.
        var detailReads = 0
    }

    let state = ReviewsLocked(State())

    func fetchPulls(host: RemoteHost, state list: PullListState, token: String) async throws -> [PullRequest] {
        let (delay, gate) = state { state in
            state.running += 1
            state.mostRunning = max(state.mostRunning, state.running)
            return (state.delay, state.gates[host.slug])
        }
        defer { state { $0.running -= 1 } }
        if let gate { await gate.wait() }
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
        let gate = state { state in
            state.detailReads += 1
            return state.detailGates[number]
        }
        if let gate { await gate.wait() }
        let found = try state { state in
            if let error = state.detailFailures[token] { throw error }
            return state.lists[host.slug]?.first { $0.number == number }
        }
        guard let pull = found else { throw PullRequestFetchError.notFound }
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

/// The account's repos, 50 to a page, then an empty one.
final class ReviewsFakeBrowser: RemoteRepoBrowsing, Sendable {
    struct State {
        var members: [RemoteRepoSummary] = []
        /// What a token lists instead of `members`.
        var membersByToken: [String: [RemoteRepoSummary]] = [:]
        /// Listed after the members of any token: the clones, when the harness makes them members.
        var clones: [RemoteRepoSummary] = []
        var failure: PullRequestFetchError?
        /// Reads of the first page: one per membership listing.
        var listings = 0
        /// The highest page asked for.
        var mostPages = 0
    }

    static let pageSize = RemoteRepoBrowserFactory.pageSize

    let state = ReviewsLocked(State())

    func fetchUserRepos(apiBase: URL, token: String, page: Int) async throws -> [RemoteRepoSummary] {
        try state { state in
            if page == 1 { state.listings += 1 }
            state.mostPages = max(state.mostPages, page)
            if let failure = state.failure { throw failure }
            let all = (state.membersByToken[token] ?? state.members) + state.clones
            return Array(all.dropFirst((page - 1) * Self.pageSize).prefix(Self.pageSize))
        }
    }
}

/// Fixed hits, and the login each read was made with.
final class ReviewsFakeActivity: ReviewActivitySource, Sendable {
    struct State {
        var hits: [ActivityHit] = []
        var failure: PullRequestFetchError?
        var logins: [String] = []
    }

    let state = ReviewsLocked(State())

    func recentActivity(apiBase: URL, login: String, since: Date, token: String) async throws -> [ActivityHit] {
        try state { state in
            state.logins.append(login)
            if let failure = state.failure { throw failure }
            return state.hits
        }
    }
}

/// Scripted host search: where each repo lives now and what a lookup throws,
/// by the path asked, fixed search results, searches held on a gate, and a log
/// of what was asked.
final class ReviewsFakeSearch: HostSearching, Sendable {
    /// One call to `searchPulls` or `searchRepos`.
    struct SearchCall: Equatable {
        enum Kind: Equatable { case pulls, repos }
        let kind: Kind
        let text: String
        let owners: [String]?
    }

    struct State {
        /// The current path of each path asked (`owner/repo`); a `nil` value
        /// is a 404, set with `.some(nil)`. A path not listed hasn't moved.
        var paths: [String: String?] = [:]
        /// What a lookup throws, by the path asked.
        var pathFailures: [String: PullRequestFetchError] = [:]
        /// Calls to `currentPath`.
        var lookups = 0
        var pulls: [FoundPull] = []
        var repos: [FoundRepo] = []
        /// Each search, in the order it was made.
        var searches: [SearchCall] = []
        /// What every search throws.
        var failure: PullRequestFetchError?
        /// Holds the searches for a text until its gate opens.
        var gates: [String: AsyncGate] = [:]
    }

    let state = ReviewsLocked(State())

    func searchPulls(_ text: String, owners: [String]?, on instance: HostingInstance,
                     token: String) async throws -> [FoundPull] {
        try await search(SearchCall(kind: .pulls, text: text, owners: owners)) { $0.pulls }
    }

    func searchRepos(_ text: String, owners: [String]?, on instance: HostingInstance,
                     token: String) async throws -> [FoundRepo] {
        try await search(SearchCall(kind: .repos, text: text, owners: owners)) { $0.repos }
    }

    func currentPath(of host: RemoteHost, token: String) async throws -> String? {
        try state { state in
            state.lookups += 1
            if let failure = state.pathFailures[host.slug] { throw failure }
            if let path = state.paths[host.slug] { return path }
            return host.slug
        }
    }

    private func search<Found>(_ call: SearchCall, results: (State) -> [Found]) async throws -> [Found] {
        let gate = state { state in
            state.searches.append(call)
            return state.gates[call.text]
        }
        if let gate { await gate.wait() }
        return try state { state in
            if let failure = state.failure { throw failure }
            return results(state)
        }
    }
}

/// Accounts on `gitlab.example.test`, their clones, the fakes, the clock
/// and the folder of the snapshot and the settings; `makeStore` builds a
/// store on them, as a launch.
@MainActor
final class ReviewsHarness {
    static let instance = HostingInstance(kind: .gitlab, host: "gitlab.example.test")

    /// In store order.
    var accounts: [HostingAccount]
    let provider = ReviewsFakeProvider()
    let browser = ReviewsFakeBrowser()
    let activity = ReviewsFakeActivity()
    var search = ReviewsFakeSearch()
    var locals: [LocalRemote] = [] { didSet { syncClones() } }
    /// Whether the membership also lists the clones. A clone counts only when
    /// an account belongs to its repo, so a test about something else keeps
    /// this on; the membership tests turn it off and list their own members
    /// in `browser`.
    var clonesAreMembers = true { didSet { syncClones() } }
    /// The token an account gets instead of the one `answer` gives, by account id.
    var tokenFor: [UUID: PullRequestAuthResult] = [:]
    /// Holds `localRemotes` until opened, when set.
    var localsGate: AsyncGate?
    /// Calls to `localRemotes`.
    private(set) var localReads = 0
    var now = ReviewsHarness.date(1_790_000_000)
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
                if let fixed = tokenFor[accountId] { return fixed }
                if let rejected { renewals.append(rejected) }
                return answer(rejected)
            },
            makeProvider: { [provider] _ in provider },
            makeBrowser: { [browser] _ in browser },
            makeActivity: { [activity] _ in activity },
            makeSearch: { [self] _ in search },
            snapshots: ReviewsSnapshotStore(directory: directory),
            config: ReviewsConfigStore(directory: directory),
            now: { [self] in now },
            makeReviewProvider: { [provider] _ in provider }))
    }

    private func syncClones() {
        let clones = clonesAreMembers ? locals.map { Self.member("clone:\($0.host.slug)", $0.host.slug) } : []
        browser.state { $0.clones = clones }
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

    /// A clone of team/app, and recent activity in team/api, a repo the
    /// account belongs to.
    static func twoRepos(login: String? = "marta") -> ReviewsHarness {
        let harness = ReviewsHarness(login: login)
        harness.locals = [local("team/app")]
        harness.browser.state { $0.members = [member("2", "team/api")] }
        harness.activity.state { $0.hits = [ActivityHit(ref: .projectId("2"), at: date(1_789_000_000))] }
        return harness
    }
}
