import Foundation

@MainActor
extension ReviewsStore {
    /// Which inbox a preview shows. Every one is invented data on fake hosts:
    /// nothing touches the network, the keychain or the user's snapshot.
    enum PreviewInbox {
        /// A clone, two repos that aren't cloned (one on GitHub), a draft
        /// and a repo that answers 403.
        case loaded
        /// Accounts, but no repo with an open pull request.
        case empty
        case noAccounts
        /// `loaded` plus more repos than `FollowedRepos.limit`.
        case overLimit
        /// `loaded` plus an account to connect again.
        case attention
    }

    /// A store on `PreviewReviewsWorld`. Empty until it refreshes, which
    /// `ReviewsView` does when it appears.
    static func preview(_ inbox: PreviewInbox = .loaded) -> ReviewsStore {
        ReviewsStore(environment: PreviewReviewsWorld(inbox).environment)
    }

    /// Reads the preview world to the end, even when the view's own read
    /// started first (a refresh does nothing while one runs): what a preview
    /// does next needs the followed repos.
    func refreshForPreview() async {
        await refresh(force: true)
        while isRefreshing { try? await Task.sleep(for: .milliseconds(50)) }
    }

    /// Opens `PreviewReviewsWorld.otherLinks` in order: the last one is at
    /// the top of the Others, selected.
    func openPreviewOthers() async {
        await refreshForPreview()
        for link in PreviewReviewsWorld.otherLinks { _ = await openLink(link) }
    }

    /// Narrows the inbox to the followed repo at `path` on the GitLab instance.
    func showPreviewRepo(_ path: String) async {
        await refreshForPreview()
        showRepo(FollowedRepos.key(RemoteHost.make(fullName: path, on: PreviewReviewsWorld.gitLab)!))
    }

    /// Opens `PreviewReviewsWorld.slowLink`, whose detail never comes: the
    /// detail column says what it's opening for as long as the preview runs.
    func openPreviewSlowLink() async {
        await refreshForPreview()
        _ = await openLink(PreviewReviewsWorld.slowLink)
    }
}

/// The fake hosts behind `ReviewsStore.preview`: accounts on
/// `gitlab.example.test` and github.com, their memberships, activity and open
/// pull requests, the detail of each, and pull requests only a link reaches.
@MainActor
struct PreviewReviewsWorld {
    static let gitLab = HostingInstance(id: UUID(uuidString: "00000000-0000-0000-0000-00000000A001")!,
                                        kind: .gitlab, host: "gitlab.example.test")
    static let gitHub = HostingInstance(id: UUID(uuidString: "00000000-0000-0000-0000-00000000A002")!,
                                        kind: .github, host: "github.com")
    static let marta = HostingAccount(id: UUID(uuidString: "00000000-0000-0000-0000-00000000B001")!,
                                      instanceId: gitLab.id, login: "marta", method: .oauth, status: .ok)
    static let octo = HostingAccount(id: UUID(uuidString: "00000000-0000-0000-0000-00000000B002")!,
                                     instanceId: gitHub.id, login: "octo", method: .oauth, status: .ok)
    /// Its token was rejected: the inbox asks to connect it again.
    static let martaOps = HostingAccount(id: UUID(uuidString: "00000000-0000-0000-0000-00000000B003")!,
                                         instanceId: gitLab.id, login: "marta.ops", method: .personalToken,
                                         status: .needsAttention(.expired))

    /// The clone on this Mac.
    static let paymentsApp = "apps/payments/android/payments-app"
    static let ledger = "apps/payments/backend/ledger"
    /// Answers 403.
    static let infraModules = "apps/platform/infra-modules"
    static let designTokens = "octo-org/design-tokens"
    /// Followed, with no open pull request.
    static let releaseTools = "apps/platform/release-tools"
    /// On github.com, and nobody follows it: its pull requests open as Others.
    static let ossLib = "oss/lib"
    /// A merged pull request of a followed repo, then an open one of
    /// `ossLib`, as `ReviewsStore.openPreviewOthers` opens them.
    static let otherLinks = [
        link("https://gitlab.example.test/\(paymentsApp)/-/merge_requests/466"),
        link("https://github.com/\(ossLib)/pull/12"),
    ]
    /// A pull request of `ossLib` whose detail never comes.
    static let slowLink = link("https://github.com/\(ossLib)/pull/15")
    /// Repos past `FollowedRepos.limit` in `overLimit`.
    static let fillerCount = 101

    let environment: ReviewsEnvironment

    init(_ inbox: ReviewsStore.PreviewInbox) {
        let now = Date.now
        let accounts: [(account: HostingAccount, instance: HostingInstance)]
        switch inbox {
        case .noAccounts: accounts = []
        case .empty: accounts = [(Self.marta, Self.gitLab)]
        case .loaded, .overLimit: accounts = [(Self.marta, Self.gitLab), (Self.octo, Self.gitHub)]
        case .attention:
            accounts = [(Self.marta, Self.gitLab), (Self.octo, Self.gitHub), (Self.martaOps, Self.gitLab)]
        }
        let populated = inbox != .empty && inbox != .noAccounts
        let fillers = inbox == .overLimit ? Self.fillerCount : 0

        let local = populated
            ? [LocalRemote(host: RemoteHost.make(fullName: Self.paymentsApp, on: Self.gitLab)!,
                           repository: Repository(url: URL(fileURLWithPath: "/Users/preview/Developer/payments-app"),
                                                  lastOpenedAt: now.addingTimeInterval(-3600)),
                           assignedAccountId: Self.marta.id)]
            : []
        let gitLabMembers = populated ? Self.gitLabMembers(fillers: fillers) : []
        let gitLabHits = populated ? Self.gitLabHits(now: now, fillers: fillers) : []
        let gitHubMembers = populated ? [Self.member("201", Self.designTokens, on: Self.gitHub)] : []
        let gitHubHits = populated ? [ActivityHit(ref: .path(Self.designTokens), at: now.addingTimeInterval(-1800))] : []
        let host = PreviewReviewsHost(lists: populated ? Self.lists(now: now) : [:],
                                      linked: populated ? Self.linked(now: now) : [:],
                                      failures: [Self.infraModules: .forbidden],
                                      slowDetails: ["\(Self.ossLib)#\(Self.slowLink.number)"])
        let snapshots = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitForge-previews/reviews-\(UUID().uuidString)", isDirectory: true)

        environment = ReviewsEnvironment(
            accounts: { accounts },
            localRemotes: { local },
            token: { accountId, _ in
                accountId == Self.martaOps.id
                    ? .connectAccount(instanceId: Self.gitLab.id, replacing: accountId)
                    : .token("preview-token")
            },
            makeProvider: { _ in host },
            makeBrowser: { kind in PreviewRepoBrowser(members: kind == .gitlab ? gitLabMembers : gitHubMembers) },
            makeActivity: { kind in PreviewActivity(hits: kind == .gitlab ? gitLabHits : gitHubHits) },
            snapshots: ReviewsSnapshotStore(directory: snapshots),
            makeReviewProvider: { _ in host })
    }

    // MARK: Data

    private static func link(_ url: String) -> PullRequestLink {
        PullRequestLink.parse(url, instances: [gitLab, gitHub])!
    }

    private static func member(_ id: String, _ path: String, on instance: HostingInstance) -> RemoteRepoSummary {
        RemoteRepoSummary(id: id, name: String(path.split(separator: "/").last ?? ""), fullName: path,
                          description: nil, sshURL: nil, httpsURL: "https://\(instance.host)/\(path).git",
                          isPrivate: true, defaultBranch: "main")
    }

    private static func gitLabMembers(fillers: Int) -> [RemoteRepoSummary] {
        // The clone is listed too: a clone counts only when the account belongs to its repo.
        [member("101", paymentsApp, on: gitLab), member("102", ledger, on: gitLab),
         member("103", infraModules, on: gitLab), member("104", releaseTools, on: gitLab)]
            + (0..<fillers).map { member("9\($0)", "apps/archive/service-\($0)", on: gitLab) }
    }

    /// The fillers are older than the rest, so they're the ones left out.
    private static func gitLabHits(now: Date, fillers: Int) -> [ActivityHit] {
        [ActivityHit(ref: .projectId("102"), at: now.addingTimeInterval(-2 * 3600)),
         ActivityHit(ref: .projectId("103"), at: now.addingTimeInterval(-5 * 3600)),
         ActivityHit(ref: .projectId("104"), at: now.addingTimeInterval(-26 * 3600))]
            + (0..<fillers).map { ActivityHit(ref: .projectId("9\($0)"), at: now.addingTimeInterval(-Double(2 + $0) * 86_400)) }
    }

    private static func pull(_ number: Int, _ title: String, by author: String, from branch: String,
                             into target: String = "main", state: PullRequest.State = .open, minutesAgo: Double,
                             on path: String, instance: HostingInstance, now: Date) -> PullRequest {
        let segment = instance.kind == .gitlab ? "-/merge_requests" : "pull"
        return PullRequest(id: "\(path)#\(number)", number: number, title: title, state: state,
                           authorLogin: author, authorAvatarURL: nil, sourceBranch: branch, targetBranch: target,
                           webURL: URL(string: "https://\(instance.host)/\(path)/\(segment)/\(number)"),
                           createdAt: now.addingTimeInterval(-minutesAgo * 60 - 86_400),
                           updatedAt: now.addingTimeInterval(-minutesAgo * 60), headSha: "a1b2c3d\(number)")
    }

    /// Pull requests no open list has: of `ossLib`, and merged.
    private static func linked(now: Date) -> [String: [PullRequest]] {
        [
            paymentsApp: [
                pull(466, "Keep the basket when the session expires", by: "jon", from: "fix/basket-session",
                     into: "develop", state: .merged, minutesAgo: 4300, on: paymentsApp, instance: gitLab, now: now),
            ],
            ossLib: [
                pull(12, "Parse dates in the server's time zone", by: "octo", from: "fix/server-time-zone",
                     minutesAgo: 70, on: ossLib, instance: gitHub, now: now),
            ],
        ]
    }

    private static func lists(now: Date) -> [String: [PullRequest]] {
        [
            paymentsApp: [
                pull(482, "Retry card authorisation after a gateway timeout", by: "lucia",
                     from: "fix/card-auth-gateway-timeout-retry", into: "develop", minutesAgo: 25,
                     on: paymentsApp, instance: gitLab, now: now),
                pull(479, "Split the checkout screen into steps", by: "jon", from: "feat/checkout-steps",
                     into: "develop", state: .draft, minutesAgo: 190, on: paymentsApp, instance: gitLab, now: now),
                pull(470, "Show the refund reason on the receipt", by: "marta", from: "feat/refund-reason",
                     into: "develop", minutesAgo: 1500, on: paymentsApp, instance: gitLab, now: now),
            ],
            ledger: [
                pull(1203, "Round half-even in the monthly statement", by: "pablo", from: "fix/statement-rounding",
                     minutesAgo: 130, on: ledger, instance: gitLab, now: now),
            ],
            designTokens: [
                pull(88, "Add elevated surface colours for dark mode", by: "sam", from: "feat/dark-elevated",
                     minutesAgo: 50, on: designTokens, instance: gitHub, now: now),
                pull(85, "Build the tokens with Node 22", by: "octo", from: "chore/node-22",
                     minutesAgo: 2900, on: designTokens, instance: gitHub, now: now),
            ],
        ]
    }
}

/// Open lists, pull requests only a link reaches and failures by
/// `owner/repo`; any pull request opens with a sample detail, a couple of
/// commits and files, and passing checks. Writes do nothing.
struct PreviewReviewsHost: PullRequestProvider, PullRequestReviewProvider {
    let lists: [String: [PullRequest]]
    var linked: [String: [PullRequest]] = [:]
    let failures: [String: PullRequestFetchError]
    /// `owner/repo#number` of the details that take an hour to come.
    var slowDetails: Set<String> = []

    func fetchPulls(host: RemoteHost, state: PullListState, token: String) async throws -> [PullRequest] {
        if let failure = failures[host.slug] { throw failure }
        return state == .open ? lists[host.slug] ?? [] : []
    }

    func fetchCurrentUser(host: RemoteHost, token: String) async throws -> String { "marta" }

    func fetchChecks(host: RemoteHost, pull: PullRequest, token: String) async throws -> [CICheck] {
        [CICheck(name: "unit-tests", context: "test", state: .passed, duration: 312, failureMessage: nil, webURL: nil),
         CICheck(name: "lint", context: "test", state: .passed, duration: 48, failureMessage: nil, webURL: nil),
         CICheck(name: "assemble-release", context: "build", state: .passed, duration: 541, failureMessage: nil,
                 webURL: nil)]
    }

    func fetchCommitChecks(host: RemoteHost, sha: String, token: String) async throws -> [CICheck] { [] }

    func fetchDetail(host: RemoteHost, number: Int, token: String) async throws -> PullRequestDetail {
        if slowDetails.contains("\(host.slug)#\(number)") { try await Task.sleep(for: .seconds(3600)) }
        let pulls = (lists[host.slug] ?? []) + (linked[host.slug] ?? [])
        guard let pull = pulls.first(where: { $0.number == number }) else {
            throw PullRequestFetchError.notFound
        }
        return PullRequestDetail(
            pull: pull,
            descriptionMarkdown: "Retries the authorisation once when the gateway times out, with the same idempotency key.\n\n- Keeps the first attempt's key\n- Logs both attempts",
            labels: ["payments"],
            reviewers: [.init(login: "marta", state: .pending), .init(login: "pablo", state: .approved)],
            assignees: [pull.authorLogin ?? ""],
            mergeable: number != 88,
            ciStatus: CIStatus(state: .success, description: nil, webURL: nil))
    }

    func fetchCommits(host: RemoteHost, number: Int, token: String) async throws -> [PullRequestCommit] {
        PullRequestCommit.previewSamples
    }

    func fetchFiles(host: RemoteHost, number: Int, token: String) async throws -> [PullRequestFileChange] {
        PullRequestFileChange.previewSamples
    }

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

/// One page with every member, then an empty one.
struct PreviewRepoBrowser: RemoteRepoBrowsing {
    let members: [RemoteRepoSummary]

    func fetchUserRepos(apiBase: URL, token: String, page: Int) async throws -> [RemoteRepoSummary] {
        page == 1 ? members : []
    }
}

struct PreviewActivity: ReviewActivitySource {
    let hits: [ActivityHit]

    func recentActivity(apiBase: URL, login: String, since: Date, token: String) async throws -> [ActivityHit] {
        hits
    }
}
