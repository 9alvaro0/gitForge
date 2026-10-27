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
        /// `loaded` plus two more Android apps followed by activity and two
        /// that aren't: gitForge proposes `apps/*/android/*`.
        case proposal
        /// `proposal` with so many more Android apps that following the
        /// pattern would pass `FollowedRepos.limit`.
        case proposalOverLimit
        /// What Settings › Reviews shows: `proposal` with
        /// `androidPattern` accepted, oss/lib followed by hand, a clone whose
        /// repo moved, a hidden repo, a third platform repo followed by
        /// activity (gitForge proposes `apps/platform/*`) and a few members
        /// nobody follows, for "Add repository…".
        case settings
        /// `settings` plus `toolFillerCount` members under `tools/legacy`:
        /// a pattern for them would pass `FollowedRepos.limit`.
        case settingsOverLimit
    }

    /// A store on `PreviewReviewsWorld`. Empty until it refreshes, which
    /// `PullsView` does when it appears.
    static func preview(_ inbox: PreviewInbox = .loaded) -> ReviewsStore {
        ReviewsStore(environment: PreviewReviewsWorld(inbox).environment)
    }

    /// `preview(inbox)` with `repository` open in gitForge, as `AppState`
    /// hands it over (U1 Ruling 3), and on `tab`, as if it was the one saved.
    static func preview(_ inbox: PreviewInbox = .loaded, open repository: PreviewOpenRepository?,
                        tab: PullsTab = .team) -> ReviewsStore {
        var environment = PreviewReviewsWorld(inbox).environment
        let active = repository?.active
        environment.activeRepository = { active }
        environment.loadTab = { tab }
        return ReviewsStore(environment: environment)
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

    /// Selects the row `id` once the preview world is read, as a click on it
    /// does: a selection the list doesn't show when it appears is dropped.
    func selectPreviewRow(_ id: InboxPull.ID) async {
        await refreshForPreview()
        selectedID = id
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

    /// Opens the repo at `path` on github.com as "Search all" finds it:
    /// nobody follows it, so the inbox is narrowed to it and offers to follow
    /// it (`PreviewReviewsWorld.ossLib` has open pull requests,
    /// `PreviewReviewsWorld.ossCli` none).
    func openPreviewFoundRepo(_ path: String) async {
        await refreshForPreview()
        let host = RemoteHost.make(fullName: path, on: PreviewReviewsWorld.gitHub)!
        _ = await openFoundRepo(FoundRepo(host: host, instanceId: PreviewReviewsWorld.gitHub.id,
                                          cloneURL: "https://github.com/\(path).git"))
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
    /// On github.com, nobody follows it and it has no open pull request.
    static let ossCli = "oss/cli"
    /// Followed by activity in `proposal`, with the clone: three Android apps
    /// of the same shape.
    static let weatherApp = "apps/weather/android/weather-app"
    static let notesApp = "apps/notes/android/notes-app"
    /// Of the same shape in `proposal`, and not followed.
    static let siblingApps = ["apps/maps/android/maps-app", "apps/chat/android/chat-app"]
    /// More Android apps in `proposalOverLimit`, not followed either.
    static let siblingFillerCount = 100
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
    /// The pattern accepted in `settings`.
    static let androidPattern = FollowPattern(host: gitLab.host, text: "apps/*/android/*")!
    /// The path the second clone's `origin` still has in `settings`: the
    /// repo is `ledger` now.
    static let ledgerOldPath = "apps/payments/backend/ledger-api"
    /// Followed by activity and hidden in `settings`.
    static let ledgerSandbox = "apps/payments/backend/ledger-sandbox"
    /// Followed by activity in `settings`, with `infraModules` and
    /// `releaseTools`.
    static let buildCache = "apps/platform/build-cache"
    /// Members nobody follows in `settings`, on the GitLab instance and on
    /// github.com.
    static let unfollowedGitLab = ["apps/platform/feature-flags", "apps/payments/web/checkout-web",
                                   "apps/fitness/backend/sync-service"]
    static let unfollowedGitHub = ["oss/cli", "octo/dotfiles"]
    /// Members under `tools/legacy` in `settingsOverLimit`.
    static let toolFillerCount = 100

    let environment: ReviewsEnvironment

    init(_ inbox: ReviewsStore.PreviewInbox) {
        let now = Date.now
        let accounts: [(account: HostingAccount, instance: HostingInstance)]
        switch inbox {
        case .noAccounts: accounts = []
        case .empty: accounts = [(Self.marta, Self.gitLab)]
        case .loaded, .overLimit, .proposal, .proposalOverLimit, .settings, .settingsOverLimit:
            accounts = [(Self.marta, Self.gitLab), (Self.octo, Self.gitHub)]
        case .attention:
            accounts = [(Self.marta, Self.gitLab), (Self.octo, Self.gitHub), (Self.martaOps, Self.gitLab)]
        }
        let populated = inbox != .empty && inbox != .noAccounts
        let fillers = inbox == .overLimit ? Self.fillerCount : 0
        let siblings: Siblings = switch inbox {
        case .proposal, .settings, .settingsOverLimit: .proposing
        case .proposalOverLimit: .proposingOverLimit
        default: .absent
        }
        let settings: SettingsExtras = switch inbox {
        case .settings: .present
        case .settingsOverLimit: .overLimit
        default: .absent
        }

        var local = populated
            ? [LocalRemote(host: RemoteHost.make(fullName: Self.paymentsApp, on: Self.gitLab)!,
                           repository: Repository(url: Self.cloneURL(of: Self.paymentsApp),
                                                  lastOpenedAt: now.addingTimeInterval(-3600)),
                           assignedAccountId: Self.marta.id)]
            : []
        if settings != .absent {
            // Its repo moved: the inbox follows it as `ledger`.
            local.append(LocalRemote(host: RemoteHost.make(fullName: Self.ledgerOldPath, on: Self.gitLab)!,
                                     repository: Repository(url: Self.cloneURL(of: Self.ledgerOldPath),
                                                            lastOpenedAt: now.addingTimeInterval(-3 * 86_400)),
                                     assignedAccountId: Self.marta.id))
        }
        let gitLabMembers = populated ? Self.gitLabMembers(fillers: fillers, siblings: siblings, settings: settings) : []
        let gitLabHits = populated ? Self.gitLabHits(now: now, fillers: fillers, siblings: siblings, settings: settings)
            : []
        let gitHubMembers = populated ? Self.gitHubMembers(settings: settings) : []
        let gitHubHits = populated ? [ActivityHit(ref: .path(Self.designTokens), at: now.addingTimeInterval(-1800))] : []
        let host = PreviewReviewsHost(lists: populated ? Self.lists(now: now) : [:],
                                      linked: populated ? Self.linked(now: now) : [:],
                                      failures: [Self.infraModules: .forbidden],
                                      slowDetails: ["\(Self.ossLib)#\(Self.slowLink.number)"])
        let snapshots = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitForge-previews/reviews-\(UUID().uuidString)", isDirectory: true)
        let config = ReviewsConfigStore(directory: snapshots)
        if settings != .absent {
            config.save(ReviewsConfig(patterns: [Self.androidPattern],
                                      manual: [RemoteHost.make(fullName: Self.ossLib, on: Self.gitHub)!],
                                      hidden: [RemoteHost.make(fullName: Self.ledgerSandbox, on: Self.gitLab)!],
                                      answeredProposals: [Self.androidPattern.id]))
        }

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
            makeSearch: { _ in PreviewHostSearch(moved: [Self.ledgerOldPath: Self.ledger]) },
            snapshots: ReviewsSnapshotStore(directory: snapshots),
            config: config,
            makeReviewProvider: { _ in host })
    }

    /// Where the clone of the repo at `path` is on this Mac.
    static func cloneURL(of path: String) -> URL {
        URL(fileURLWithPath: "/Users/preview/Developer/\(path.split(separator: "/").last ?? "")")
    }

    /// The Pull requests store of the clone of `path`, as its repository
    /// reads it: the preview hosts' open pull requests, marta's login and no
    /// closed one. Already read, so it shows before its own load lands, which
    /// reads the same. `connected: false` has no account to read it with: it
    /// asks to connect one. `accountChosen: false` has several, and the
    /// chooser is closed without picking one each time it's asked.
    static func repositoryStore(_ path: String, on instance: HostingInstance,
                                connected: Bool = true, accountChosen: Bool = true) -> PullRequestStore {
        let host = RemoteHost.make(fullName: path, on: instance)!
        let provider = PreviewReviewsHost(lists: lists(now: .now), failures: [:])
        let auth: @MainActor (RemoteHost, String?) async -> PullRequestAuthResult = { _, _ in
            guard accountChosen else { return .cancelled }
            return connected ? .token("preview-token") : .connectAccount(instanceId: instance.id, replacing: nil)
        }
        let store = PullRequestStore(cli: nil, auth: auth, silentAuth: auth, resolveHost: { host },
                                     makeProvider: { _ in provider }, makeReviewProvider: { _ in provider })
        store.host = host
        if !accountChosen {
            store.accountNotChosen = true
        } else if connected {
            store.items = provider.lists[path] ?? []
            store.currentUser = "marta"
        } else {
            store.requiresToken = true
            store.connectInstanceId = instance.id
        }
        return store
    }

    // MARK: Data

    /// The Android apps besides payments-app.
    private enum Siblings {
        case absent
        /// `weatherApp` and `notesApp` followed by activity, and `siblingApps`.
        case proposing
        /// `proposing` plus `siblingFillerCount` more members.
        case proposingOverLimit
    }

    /// What `settings` adds.
    private enum SettingsExtras {
        case absent
        /// `ledgerSandbox` and `buildCache` followed by activity, and the
        /// unfollowed members.
        case present
        /// `present` plus `toolFillerCount` members.
        case overLimit
    }

    private static func link(_ url: String) -> PullRequestLink {
        PullRequestLink.parse(url, instances: [gitLab, gitHub])!
    }

    private static func member(_ id: String, _ path: String, on instance: HostingInstance) -> RemoteRepoSummary {
        RemoteRepoSummary(id: id, name: String(path.split(separator: "/").last ?? ""), fullName: path,
                          description: nil, sshURL: nil, httpsURL: "https://\(instance.host)/\(path).git",
                          isPrivate: true, defaultBranch: "main")
    }

    private static func gitLabMembers(fillers: Int, siblings: Siblings, settings: SettingsExtras) -> [RemoteRepoSummary] {
        // The clone is listed too: a clone counts only when the account belongs to its repo.
        // Appended step by step: long `+` chains outran the Xcode 26 type checker on CI.
        var members: [RemoteRepoSummary] = [member("101", paymentsApp, on: gitLab), member("102", ledger, on: gitLab),
                                            member("103", infraModules, on: gitLab),
                                            member("104", releaseTools, on: gitLab)]
        for index in 0..<fillers {
            members.append(member("9\(index)", "apps/archive/service-\(index)", on: gitLab))
        }
        if siblings != .absent {
            members.append(contentsOf: [member("105", weatherApp, on: gitLab), member("106", notesApp, on: gitLab)])
            for (offset, path) in siblingApps.enumerated() {
                members.append(member("10\(7 + offset)", path, on: gitLab))
            }
        }
        if siblings == .proposingOverLimit {
            members += (0..<siblingFillerCount).map {
                member("8\($0)", "apps/brand-\($0)/android/brand-\($0)-app", on: gitLab)
            }
        }
        if settings != .absent {
            members.append(member("110", ledgerSandbox, on: gitLab))
            members.append(member("111", buildCache, on: gitLab))
            for (offset, path) in unfollowedGitLab.enumerated() {
                members.append(member("11\(2 + offset)", path, on: gitLab))
            }
        }
        if settings == .overLimit {
            for index in 0..<toolFillerCount {
                members.append(member("7\(index)", "tools/legacy/script-\(index)", on: gitLab))
            }
        }
        return members
    }

    private static func gitHubMembers(settings: SettingsExtras) -> [RemoteRepoSummary] {
        var members: [RemoteRepoSummary] = [member("201", designTokens, on: gitHub)]
        guard settings != .absent else { return members }
        for (offset, path) in ([ossLib] + unfollowedGitHub).enumerated() {
            members.append(member("20\(2 + offset)", path, on: gitHub))
        }
        return members
    }

    /// The fillers are older than the rest, so they're the ones left out.
    private static func gitLabHits(now: Date, fillers: Int, siblings: Siblings,
                                   settings: SettingsExtras) -> [ActivityHit] {
        // Built step by step: as one expression it outran the Xcode 26 type checker on CI.
        func hit(_ id: String, hoursAgo: Double) -> ActivityHit {
            ActivityHit(ref: .projectId(id), at: now.addingTimeInterval(-hoursAgo * 3600))
        }
        var hits: [ActivityHit] = [hit("102", hoursAgo: 2), hit("103", hoursAgo: 5), hit("104", hoursAgo: 26)]
        for index in 0..<fillers {
            hits.append(hit("9\(index)", hoursAgo: Double(2 + index) * 24))
        }
        if siblings != .absent {
            hits.append(contentsOf: [hit("105", hoursAgo: 30), hit("106", hoursAgo: 50)])
        }
        if settings != .absent {
            hits.append(contentsOf: [hit("110", hoursAgo: 60), hit("111", hoursAgo: 70)])
        }
        return hits
    }

    private static func pull(_ number: Int, _ title: String, by author: String, from branch: String,
                             into target: String = "main", state: PullRequest.State = .open,
                             status: PullListStatus.Kind? = nil, minutesAgo: Double,
                             on path: String, instance: HostingInstance, now: Date) -> PullRequest {
        let segment = instance.kind == .gitlab ? "-/merge_requests" : "pull"
        return PullRequest(id: "\(path)#\(number)", number: number, title: title, state: state,
                           authorLogin: author, authorAvatarURL: nil, sourceBranch: branch, targetBranch: target,
                           webURL: URL(string: "https://\(instance.host)/\(path)/\(segment)/\(number)"),
                           createdAt: now.addingTimeInterval(-minutesAgo * 60 - 86_400),
                           updatedAt: now.addingTimeInterval(-minutesAgo * 60), headSha: "a1b2c3d\(number)",
                           listStatus: status.map { PullListStatus(kind: $0) })
    }

    /// Pull requests no open list has: merged ones.
    private static func linked(now: Date) -> [String: [PullRequest]] {
        [
            paymentsApp: [
                pull(466, "Keep the basket when the session expires", by: "jon", from: "fix/basket-session",
                     into: "develop", state: .merged, minutesAgo: 4300, on: paymentsApp, instance: gitLab, now: now),
            ],
        ]
    }

    private static func lists(now: Date) -> [String: [PullRequest]] {
        [
            paymentsApp: [
                pull(482, "Retry card authorisation after a gateway timeout", by: "lucia",
                     from: "fix/card-auth-gateway-timeout-retry", into: "develop", status: .ready, minutesAgo: 25,
                     on: paymentsApp, instance: gitLab, now: now),
                pull(479, "Split the checkout screen into steps", by: "jon", from: "feat/checkout-steps",
                     into: "develop", state: .draft, minutesAgo: 190, on: paymentsApp, instance: gitLab, now: now),
                pull(470, "Show the refund reason on the receipt", by: "marta", from: "feat/refund-reason",
                     into: "develop", status: .needsApproval, minutesAgo: 1500, on: paymentsApp, instance: gitLab, now: now),
            ],
            ledger: [
                pull(1203, "Round half-even in the monthly statement", by: "pablo", from: "fix/statement-rounding",
                     status: .failing, minutesAgo: 130, on: ledger, instance: gitLab, now: now),
            ],
            designTokens: [
                pull(88, "Add elevated surface colours for dark mode", by: "sam", from: "feat/dark-elevated",
                     status: .running, minutesAgo: 50, on: designTokens, instance: gitHub, now: now),
                pull(85, "Build the tokens with Node 22", by: "octo", from: "chore/node-22",
                     status: .conflicts, minutesAgo: 2900, on: designTokens, instance: gitHub, now: now),
            ],
            // Not followed: its pull requests come in from a link or when
            // "Search all" opens the repo.
            ossLib: [
                pull(12, "Parse dates in the server's time zone", by: "octo", from: "fix/server-time-zone",
                     status: .changesRequested, minutesAgo: 70, on: ossLib, instance: gitHub, now: now),
                pull(9, "Drop the deprecated date formatter", by: "ana", from: "chore/drop-old-formatter",
                     status: .blocked, minutesAgo: 3100, on: ossLib, instance: gitHub, now: now),
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

/// Finds nothing; a repo has moved only when `moved` says so.
nonisolated struct PreviewHostSearch: HostSearching {
    /// Current paths by the old ones.
    var moved: [String: String] = [:]

    func searchPulls(_ text: String, owners: [String]?, on instance: HostingInstance,
                     token: String) async throws -> [FoundPull] { [] }
    func searchRepos(_ text: String, owners: [String]?, on instance: HostingInstance,
                     token: String) async throws -> [FoundRepo] { [] }
    func currentPath(of host: RemoteHost, token: String) async throws -> String? { moved[host.slug] ?? host.slug }
}
