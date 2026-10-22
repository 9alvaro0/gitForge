import Foundation
import Observation
import os

/// Pull / merge requests of the active repository: the open list and the
/// detail pane (overview, commits, files). Owned by `RepositoryViewModel`
/// (`viewModel.pullRequests`) but self-contained — it only needs the repo's
/// `GitCLI` to resolve the remote host, and `auth` for the token. The Reviews
/// inbox also builds one per remote repository that may not be on disk: no
/// `GitCLI`, a host and an `auth` given by the caller, and `prepareForDetail`
/// instead of a list load.
///
/// Integrating a PR locally ("Resolve locally") stays on the view model: it
/// checks out, merges and refreshes conflicts, which is session-wide work.
@Observable
@MainActor
final class PullRequestStore {
    private static let logger = Logger(subsystem: "com.warwarelabs.gitForge", category: "pulls")
    /// Minimum gap between two non-forced list loads.
    static let reloadThrottle: TimeInterval = 30

    // MARK: List
    /// Open PRs/MRs ("Open"; "Mine" filters them by author).
    var items: [PullRequest] = []
    /// Closed and merged, loaded the first time "Closed" is shown.
    var closedItems: [PullRequest] = []
    var closedLoaded = false
    var isLoadingClosed = false
    var scope: PullListScope = .open
    /// Login of the token's owner, for "Mine". `nil` until known.
    var currentUser: String?
    /// The token `currentUser` was read with: another token (a reconnect, a
    /// different account for the repo) may belong to someone else.
    private var currentUserToken: String?
    /// CI summary per PR id, filled in after the list loads.
    var ciByPull: [String: CIStatus] = [:]
    var host: RemoteHost?
    /// The `origin` host isn't an instance but looks like GitHub or GitLab:
    /// `PullsView` offers to add it.
    var suggestedInstance: InstanceSuggestion?
    var isLoading = false
    var error: String?
    /// Host detected but no account can give a token — drives the "Connect
    /// a … account" empty state in `PullsView`.
    var requiresToken = false
    /// Several accounts fit and the user closed the chooser without
    /// picking one: nothing was loaded.
    var accountNotChosen = false
    /// The instance "Connect a … account" opens on, when known.
    var connectInstanceId: UUID?
    /// The account to reconnect, when its token was rejected.
    var reconnectAccountId: UUID?
    var lastLoadedAt: Date?

    // MARK: Detail
    var selected: PullRequest?
    var detail: PullRequestDetail?
    var commits: [PullRequestCommit] = []
    var files: [PullRequestFileChange] = [] { didSet { placeThreads() } }
    var checks: [CICheck] = []
    var isLoadingDetail = false
    var detailError: String?
    /// Bumped by every detail op (`select` / `closeDetail` / `loadDetail`).
    /// The loader snapshots it on entry and drops its writes if it moved
    /// while awaiting — keeps a slow PR#1 fetch from landing on top of a
    /// freshly-selected PR#2 (or on a closed detail pane).
    var detailGen: UInt64 = 0
    /// Drives the spinner on "Resolve locally" while a try-merge runs.
    var localMergeRunning = false
    /// The PR to open once the list has it (`selectWhenLoaded`): another
    /// screen asked for it before the list was there.
    private(set) var pendingSelectionNumber: Int?

    // MARK: Review
    /// Whether the host takes "Request changes" (GitLab varies by version);
    /// read with each detail, kept across PRs of the same repo.
    var requestChangesSupport: RequestChangesSupport?
    /// Bumped by every probe for `requestChangesSupport` and by `reset`: an
    /// older probe's answer lands nowhere.
    @ObservationIgnored private var supportGen: UInt64 = 0
    /// The verdict being sent; disables the buttons meanwhile.
    var submittingReview: ReviewVerdict?
    /// The open Approve / Request changes panel. Kept here, not in the
    /// header's buttons: the header lays them out in several variants, each
    /// with its own state, and a relayout would close the panel.
    var reviewPanel: ReviewVerdict?
    /// The PR whose detail reloads after a review (`isReviewBusy`).
    var reviewSettlingPullId: String?
    /// What the user is typing in the review boxes (`ReviewDraftKey`).
    let drafts = ReviewDrafts()

    // MARK: Threads
    /// The selected PR's review threads; `placedThreads` says where each shows.
    var threads: [ReviewThread] = [] { didSet { placeThreads() } }
    private(set) var placedThreads: PlacedThreads = .empty
    /// The lines of the selected PR's patches, for `placedThreads`.
    @ObservationIgnored private var lineIndex = DiffLineIndex()
    var isLoadingThreads = false
    /// Why the threads didn't load. The diff shows all the same.
    var threadsError: String?
    /// The line a new comment is being written on. One box is open at a
    /// time (their shortcuts would collide): opening it closes the reply
    /// box, whose draft stays.
    var composerTarget: CommentTarget? {
        didSet {
            guard let composerTarget else { return }
            replyingThreadId = nil
            // The same box again is on screen already: it won't ask.
            if composerTarget != oldValue { focusRequest = .comment(pullId: selected?.id ?? "", target: composerTarget) }
        }
    }
    /// The thread whose reply box is open.
    var replyingThreadId: String? {
        didSet {
            guard let replyingThreadId else { return }
            composerTarget = nil
            if replyingThreadId != oldValue { focusRequest = .reply(pullId: selected?.id ?? "", threadId: replyingThreadId) }
        }
    }
    /// The box that takes the focus when it next comes on screen: one just
    /// opened, or one that went off screen with it (`claimFocus`).
    @ObservationIgnored var focusRequest: ReviewDraftKey?
    /// The comments and replies being sent.
    var sendingDrafts: Set<ReviewDraftKey> = []
    /// The threads being resolved or reopened.
    var resolvingThreadIds: Set<String> = []
    /// The detail the files were read with. New comments are pinned to the
    /// diff on screen, though the CI poll may have read a newer head since.
    private(set) var filesDetail: PullRequestDetail?
    /// Bumped by every thread load and by `select`: an older load lands nowhere.
    @ObservationIgnored var threadsGen: UInt64 = 0
    /// The head of the diff `threads` were read against: once the diff on
    /// screen is another, their line numbers may point at other code.
    @ObservationIgnored var threadsHead: String?

    // MARK: Merge
    /// What the merge sheet offers, read when it opens.
    var mergeOptions: MergeOptions?
    var mergeOptionsError: String?
    var isLoadingMergeOptions = false
    /// What the user set in the merge sheet.
    var mergeDraft: MergeDraft?
    var isMerging = false
    /// Just merged here: the PR stays in the detail though it left the
    /// list, until the user picks another (`pullToAutoSelect`).
    var keepsSelectionOutsideList = false
    /// Bumped when the sheet's options are dropped (closed, another PR):
    /// a read still in flight then lands nowhere.
    @ObservationIgnored var mergeOptionsGen: UInt64 = 0
    /// The host may still be working mergeability out: each detail load
    /// that finds it so reads the detail once more, a moment later.
    @ObservationIgnored private(set) var mergeStatusRecheck: Task<Void, Never>?
    // The timings below are per store, so tests can shorten them on their
    // own store without racing other suites over shared state.
    @ObservationIgnored var mergeStatusRecheckDelay: Duration = .seconds(3)
    /// While the open PR's CI runs, or the host says it's waiting, its
    /// checks and merge status are read again this often…
    @ObservationIgnored var checksPollInterval: Duration = .seconds(20)
    /// …at most this many times per load of the PR, so a check stuck in a
    /// queue doesn't keep reading the host.
    @ObservationIgnored var checksPollLimit = 45
    @ObservationIgnored private var checksPollsLeft = 0
    /// The host works the merge status out again a moment after the checks
    /// finish: while it still says blocked, it's read this many more times.
    static let settleReads = 2
    @ObservationIgnored private var settleReadsLeft = 0

    /// Where the token comes from (the repo's account).
    /// `rejected`: a token that just got a 401.
    private let auth: @MainActor (RemoteHost, _ rejected: String?) async -> PullRequestAuthResult
    /// Same as `auth`, but never asks the user to pick an account. Used by
    /// lookups the user didn't start from Pull requests (a commit's CI).
    private let silentAuth: @MainActor (RemoteHost, _ rejected: String?) async -> PullRequestAuthResult
    /// The token of the last successful list load, reused by Closed, CI and the detail.
    private var currentToken: String?
    private let resolveHost: @MainActor () async -> RemoteHost?
    private let suggestInstance: @MainActor () async -> InstanceSuggestion?
    private let makeProvider: @MainActor (RemoteHost) -> PullRequestProvider
    let makeReviewProvider: @MainActor (RemoteHost) -> PullRequestReviewProvider
    private let parsePatch: @Sendable (String) -> [DiffHunk]
    private var detailTask: Task<Void, Never>?
    private var ciTask: Task<Void, Never>?
    /// Bumped by every list load so a slow CI fill for an older list drops
    /// its writes.
    private var listGen: UInt64 = 0
    /// How many CI lookups run at once while filling the list.
    static let ciConcurrency = 6

    // MARK: Commit CI
    /// Checks per commit SHA for History's commit detail, with when they
    /// were read: re-selecting a commit within `commitChecksTTL` reuses them.
    private var commitChecksCache: [String: (checks: [CICheck], at: Date)] = [:]
    /// Token for commit lookups when the list hasn't loaded one.
    private var silentToken: String?
    static let commitChecksTTL: TimeInterval = 60
    static let commitChecksCacheCap = 64

    /// - Parameters:
    ///   - cli: the repo's `GitCLI`; `nil` for a repository that isn't on
    ///     disk, whose host then comes from `resolveHost` (none, by default).
    ///   - auth: the token for a host (the repo's account); defaults to "connect".
    ///   - resolveHost / suggestInstance / makeProvider: default to the repo's
    ///     `origin` against the built-in instances and the real GitHub /
    ///     GitLab clients; tests pass fakes.
    ///   - parsePatch: reads a file's patch to place the threads on its lines;
    ///     tests count the reads.
    init(cli: GitCLI?,
         auth: (@MainActor (RemoteHost, String?) async -> PullRequestAuthResult)? = nil,
         silentAuth: (@MainActor (RemoteHost, String?) async -> PullRequestAuthResult)? = nil,
         resolveHost: (@MainActor () async -> RemoteHost?)? = nil,
         suggestInstance: (@MainActor () async -> InstanceSuggestion?)? = nil,
         makeProvider: @escaping @MainActor (RemoteHost) -> PullRequestProvider = { PullRequestProviderFactory.make(for: $0) },
         makeReviewProvider: @escaping @MainActor (RemoteHost) -> PullRequestReviewProvider = { PullRequestReviewProviderFactory.make(for: $0) },
         parsePatch: @escaping @Sendable (String) -> [DiffHunk] = { DiffParser.parse($0) }) {
        self.auth = auth ?? { _, _ in .connectAccount(instanceId: nil, replacing: nil) }
        self.silentAuth = silentAuth ?? auth ?? { _, _ in .connectAccount(instanceId: nil, replacing: nil) }
        self.resolveHost = resolveHost ?? { await cli?.remoteHost(instances: HostingInstance.builtIns) }
        self.suggestInstance = suggestInstance ?? { nil }
        self.makeProvider = makeProvider
        self.makeReviewProvider = makeReviewProvider
        self.parsePatch = parsePatch
        lineIndex = DiffLineIndex(parse: parsePatch)
    }

    /// Asks `auth` for a token and updates the connect state; nil = no token.
    private func authorize(_ host: RemoteHost, rejected: String? = nil) async -> String? {
        accountNotChosen = false
        switch await auth(host, rejected) {
        case .token(let value):
            requiresToken = false
            connectInstanceId = nil
            reconnectAccountId = nil
            return value
        case .connectAccount(let instanceId, let replacing):
            requiresToken = true
            connectInstanceId = instanceId
            reconnectAccountId = replacing
            return nil
        case .cancelled:
            requiresToken = false
            accountNotChosen = true
            return nil
        case .failed(let message):
            requiresToken = false
            error = message
            return nil
        }
    }

    /// Runs `call` with the token of the last load; after a 401, one fresh
    /// token and one retry (a GitLab OAuth token lasts 2 h, longer than a
    /// screen may stay open). `nil` = no token to retry with.
    func withToken<T>(_ host: RemoteHost, _ call: (String) async throws -> T) async throws -> T? {
        guard let token = currentToken else { return nil }
        do {
            return try await call(token)
        } catch PullRequestFetchError.unauthorized {
            guard let fresh = await authorize(host, rejected: token) else { return nil }
            currentToken = fresh
            return try await call(fresh)
        }
    }

    // MARK: Scopes

    /// The rows the list shows for the current scope.
    var visibleItems: [PullRequest] {
        switch scope {
        case .open: items
        case .mine: items.filter { $0.authorLogin != nil && $0.authorLogin == currentUser }
        case .closed: closedItems
        }
    }

    /// Count for a scope's segment; `nil` while unknown (Closed not loaded,
    /// Mine before the user is known).
    func count(for scope: PullListScope) -> Int? {
        switch scope {
        case .open: items.count
        case .mine: currentUser == nil ? nil : items.filter { $0.authorLogin == currentUser }.count
        case .closed: closedLoaded ? closedItems.count : nil
        }
    }

    /// Switches the list; Closed is fetched the first time it's shown.
    func setScope(_ newScope: PullListScope) async {
        scope = newScope
        if newScope == .closed, !closedLoaded {
            await loadClosed()
        }
    }

    func loadClosed() async {
        guard let host, currentToken != nil, !isLoadingClosed else { return }
        isLoadingClosed = true
        defer { isLoadingClosed = false }
        let gen = listGen
        let provider = makeProvider(host)
        do {
            guard let closed = try await withToken(host, { token in
                try await provider.fetchPulls(host: host, state: .closed, token: token)
            }), let token = currentToken else { return }
            guard gen == listGen else { return }
            closedItems = closed
            closedLoaded = true
            Task { [weak self] in await self?.loadCI(for: closed, host: host, token: token, gen: gen) }
        } catch {
            guard gen == listGen else { return }
            self.error = Self.message(for: error)
        }
    }

    /// The CI summary to show for `pull`: its checks once the detail has
    /// them, otherwise the list's lookup.
    func ciStatus(for pull: PullRequest) -> CIStatus? {
        if pull.id == selected?.id, let fromChecks = CIStatus.summarize(checks) { return fromChecks }
        return ciByPull[pull.id]
    }

    /// Looks up each PR's checks in parallel, a few at a time, and keeps
    /// the summary. Failures just leave the row without a CI badge.
    private func loadCI(for pulls: [PullRequest], host: RemoteHost, token: String, gen: UInt64) async {
        let provider = makeProvider(host)
        let targets = pulls.filter { $0.headSha != nil }
        var index = 0
        await withTaskGroup(of: (String, CIStatus?).self) { group in
            func addNext() {
                guard index < targets.count else { return }
                let pull = targets[index]
                index += 1
                group.addTask {
                    let checks = try? await provider.fetchChecks(host: host, pull: pull, token: token)
                    return (pull.id, checks.flatMap { CIStatus.summarize($0) })
                }
            }
            for _ in 0..<Self.ciConcurrency { addNext() }
            for await (id, status) in group {
                if gen == listGen, let status { ciByPull[id] = status }
                addNext()
            }
        }
    }

    /// Refresh the open PR/MR list. Resolution order:
    /// 1) detect the remote host (`origin`) among the declared instances;
    ///    otherwise offer to add it
    /// 2) get a token from the repo's account; otherwise "connect", "no
    ///    account chosen" or the error
    /// 3) hit the provider, store results / error
    func load(force: Bool = false) async {
        guard !isLoading else { return }
        if !force, let lastLoadedAt, Date().timeIntervalSince(lastLoadedAt) < Self.reloadThrottle {
            return
        }

        isLoading = true
        error = nil
        defer { isLoading = false }

        listGen &+= 1
        let gen = listGen

        guard let access = await resolveAccess() else {
            items = []
            return
        }
        let resolvedHost = access.host
        var token = access.token

        let provider = makeProvider(resolvedHost)
        do {
            do {
                items = try await provider.fetchPulls(host: resolvedHost, state: .open, token: token)
            } catch PullRequestFetchError.unauthorized {
                // One fresh token (GitLab OAuth refresh), then one retry.
                guard let fresh = await authorize(resolvedHost, rejected: token) else {
                    items = []
                    currentToken = nil
                    return
                }
                token = fresh
                items = try await provider.fetchPulls(host: resolvedHost, state: .open, token: token)
            }
            currentToken = token
            lastLoadedAt = .now
        } catch {
            self.error = Self.message(for: error)
            return
        }
        // The closed list is refetched next time it's shown.
        closedLoaded = false
        closedItems = []
        await readCurrentUserIfNeeded(provider: provider, host: resolvedHost, token: token)
        // CI badges fill in afterwards, so the list (and Refresh) don't wait
        // on one lookup per row.
        let openItems = items
        ciTask?.cancel()
        ciTask = Task { [weak self] in
            await self?.loadCI(for: openItems, host: resolvedHost, token: token, gen: gen)
        }
        if scope == .closed {
            await loadClosed()
        }
    }

    /// The host and a token for it, as the list and the detail both need:
    /// the detected host (else an instance to add may be offered) and the
    /// repo's account token (else "connect", "no account chosen" or the
    /// error — `authorize` sets which). `nil` = nothing to fetch with.
    private func resolveAccess() async -> (host: RemoteHost, token: String)? {
        guard let resolvedHost = await resolveHost() else {
            host = nil
            requiresToken = false
            suggestedInstance = await suggestInstance()
            return nil
        }
        suggestedInstance = nil
        host = resolvedHost
        Self.logger.info("Pulls: detected host \(resolvedHost.host, privacy: .public) (\(resolvedHost.provider.rawValue, privacy: .public))")

        guard let token = await authorize(resolvedHost) else {
            currentToken = nil
            return nil
        }
        return (resolvedHost, token)
    }

    /// Reads the token owner's login unless it's known for this token.
    private func readCurrentUserIfNeeded(provider: PullRequestProvider, host: RemoteHost, token: String) async {
        guard currentUser == nil || currentUserToken != token else { return }
        currentUser = try? await provider.fetchCurrentUser(host: host, token: token)
        currentUserToken = currentUser == nil ? nil : token
    }

    /// Gets the store ready to open a PR's detail without the list: the
    /// host and token as `load` finds them (the same "connect" states) and
    /// the token owner's login. Reads neither the list nor the CI. `false`
    /// = no host or no token, nothing to open it with.
    func prepareForDetail() async -> Bool {
        error = nil
        guard let access = await resolveAccess() else { return false }
        currentToken = access.token
        await readCurrentUserIfNeeded(provider: makeProvider(access.host), host: access.host, token: access.token)
        return true
    }

    /// Opens `number` as soon as the list has it (`pullToAutoSelect`), for a
    /// screen that asks before the list loads. Kept until the list has it.
    func selectWhenLoaded(number: Int) {
        pendingSelectionNumber = number
    }

    /// Opens `number` now if the list shows it, else as soon as it does
    /// (`selectWhenLoaded`). `PullsView` only picks a pending number when
    /// its list changes or appears, so a list already showing it would
    /// leave it pending, to jump to it on a later reload.
    func requestSelection(number: Int) {
        if let pull = visibleItems.first(where: { $0.number == number }) {
            pendingSelectionNumber = nil
            select(pull)
        } else {
            selectWhenLoaded(number: number)
        }
    }

    /// Open the detail pane for `pr`: clears any prior detail state and
    /// starts the parallel fetch of detail / commits / files.
    func select(_ pr: PullRequest) {
        detailGen &+= 1
        selected = pr
        clearDetail()
        clearMerge()
        detailTask?.cancel()
        detailTask = Task { [weak self] in await self?.loadDetail() }
    }

    /// Reloads the open PR's detail without the caller waiting for it: a
    /// write's answer (and its toast) shouldn't wait on four reads. A
    /// select or a later load supersedes it.
    func reloadDetailInBackground(then done: (@MainActor () -> Void)? = nil) {
        // As `select` does: the load this replaces lands nowhere from now.
        detailGen &+= 1
        detailTask?.cancel()
        detailTask = Task { [weak self] in
            await self?.loadDetail()
            done?()
        }
    }

    /// Close the detail pane. The invalidated loader won't clear its own
    /// loading flag (the gen moved), so it's reset here.
    func closeDetail() {
        detailGen &+= 1
        detailTask?.cancel()
        detailTask = nil
        isLoadingDetail = false
        selected = nil
        clearDetail()
        clearMerge()
    }

    /// The PR the list should open: the one asked for with `selectWhenLoaded`
    /// once the list has it (even over another selection); else the first row
    /// when nothing is selected or the selection left the list — unless it
    /// left because it was just merged here.
    func pullToAutoSelect() -> PullRequest? {
        if let number = pendingSelectionNumber, let wanted = visibleItems.first(where: { $0.number == number }) {
            pendingSelectionNumber = nil
            return wanted
        }
        guard let selected else { return visibleItems.first }
        if visibleItems.contains(where: { $0.id == selected.id }) || keepsSelectionOutsideList { return nil }
        return visibleItems.first
    }

    /// Fetch the detail payloads in parallel, with the list's token (the
    /// list loads before any row can be selected). The first failure wins
    /// `detailError`; successful parts still render.
    func loadDetail() async {
        detailGen &+= 1
        let gen = detailGen
        // A load this one replaced won't clear the flag: the gen moved.
        guard let pr = selected, let host else {
            isLoadingDetail = false
            return
        }
        guard let token = currentToken else {
            isLoadingDetail = false
            detailError = String(localized: "The account's token isn't available. Refresh the list.")
            return
        }

        isLoadingDetail = true
        detailError = nil
        defer { if gen == detailGen { isLoadingDetail = false } }

        let provider = makeProvider(host)
        let number = pr.number
        func fetchAll(_ token: String) async -> (Result<PullRequestDetail, Error>, Result<[PullRequestCommit], Error>,
                                                 Result<[PullRequestFileChange], Error>, Result<[CICheck], Error>) {
            async let detailResult = Self.capture { try await provider.fetchDetail(host: host, number: number, token: token) }
            async let commitsResult = Self.capture { try await provider.fetchCommits(host: host, number: number, token: token) }
            async let filesResult = Self.capture { try await provider.fetchFiles(host: host, number: number, token: token) }
            async let checksResult = Self.capture { try await provider.fetchChecks(host: host, pull: pr, token: token) }
            return await (detailResult, commitsResult, filesResult, checksResult)
        }
        probeRequestChangesSupport(host: host, token: token)
        var (detail, commits, files, checks) = await fetchAll(token)
        // The token went bad since the list loaded: one fresh one, one retry.
        if case .failure(PullRequestFetchError.unauthorized) = detail,
           let fresh = await authorize(host, rejected: token) {
            currentToken = fresh
            (detail, commits, files, checks) = await fetchAll(fresh)
        }

        guard gen == detailGen else { return }
        checksPollsLeft = checksPollLimit
        settleReadsLeft = 0
        switch detail {
        case .success(let value):
            self.detail = value
            closeReviewPanelIfGone()
        case .failure(let error): detailError = Self.message(for: error)
        }
        switch commits {
        case .success(let value): self.commits = value
        case .failure(let error): if detailError == nil { detailError = Self.message(for: error) }
        }
        switch files {
        case .success(let value):
            let shownHead = filesDetail?.pull.id == pr.id ? filesDetail?.pull.headSha : nil
            self.files = value
            filesDetail = try? detail.get()
            // New commits: the open new-comment box's line number may be
            // other code now, so it closes. Its draft stays.
            if let shownHead, let head = filesDetail?.pull.headSha, head != shownHead { composerTarget = nil }
        case .failure(let error): if detailError == nil { detailError = Self.message(for: error) }
        }
        // Checks are a nice-to-have: a failure leaves the tab empty rather
        // than flagging the whole detail.
        if case .success(let value) = checks { self.checks = value }
        recheckMergeStatusIfComputing(gen: gen)
        // After the detail: GitLab tells outdated threads apart by its head.
        guard gen == detailGen else { return }
        await loadThreads()
    }

    /// Asks whether the host takes "Request changes" without holding the
    /// detail: a GitLab's first answer needs `/version` and a GraphQL probe.
    /// The buttons follow when it lands.
    private func probeRequestChangesSupport(host: RemoteHost, token: String) {
        supportGen &+= 1
        let gen = supportGen
        let provider = makeReviewProvider(host)
        Task { [weak self] in
            let support = await provider.requestChangesSupport(host: host, token: token)
            guard let self, gen == self.supportGen else { return }
            self.requestChangesSupport = support
            self.closeReviewPanelIfGone()
        }
    }

    /// One more read of the detail alone, a moment later, while the host
    /// still works out an open PR's mergeability; dropped if the detail
    /// moved on meanwhile. It never schedules another, so it can't loop.
    private func recheckMergeStatusIfComputing(gen: UInt64) {
        guard gen == detailGen, let detail, detail.hostMergeStatus?.stillComputing == true,
              detail.pull.state == .open || detail.pull.state == .draft else { return }
        let delay = mergeStatusRecheckDelay
        mergeStatusRecheck = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled, self.detailGen == gen else { return }
            await self.rereadStatus(gen: gen)
        }
    }

    /// Reads the open PR's checks and merge status again every
    /// `checksPollInterval` while its CI runs or the host is waiting, up to
    /// `checksPollLimit` reads per load. Runs as long as the caller's task:
    /// the detail view ties it to being on screen.
    func pollWhileRunning() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: checksPollInterval)
            guard !Task.isCancelled else { return }
            guard checksPollsLeft > 0, isStatusPending else { continue }
            checksPollsLeft -= 1
            let wasRunning = checksRunning
            if !wasRunning, detail?.hostMergeStatus?.verdict == .blocked { settleReadsLeft -= 1 }
            await rereadStatus(gen: detailGen)
            if wasRunning, !checksRunning { settleReadsLeft = Self.settleReads }
        }
    }

    /// The open PR's CI is still running, the host is still deciding, or
    /// the checks just finished and the host may not have caught up.
    private var isStatusPending: Bool {
        guard let selected, let detail, detail.pull.id == selected.id, !isLoadingDetail,
              detail.pull.state == .open || detail.pull.state == .draft else { return false }
        let verdict = detail.hostMergeStatus?.verdict
        return checksRunning || verdict == .waiting || (verdict == .blocked && settleReadsLeft > 0)
    }

    private var checksRunning: Bool {
        checks.contains { $0.state == .running || $0.state == .queued }
    }

    /// The detail and the checks again, keeping the files and commits
    /// shown; dropped if the detail moved on meanwhile.
    private func rereadStatus(gen: UInt64) async {
        guard let pr = selected, let host else { return }
        let provider = makeProvider(host)
        let number = pr.number
        let read = try? await withToken(host) { token in
            async let detail = provider.fetchDetail(host: host, number: number, token: token)
            async let checks = try? provider.fetchChecks(host: host, pull: pr, token: token)
            return (try await detail, await checks)
        }
        guard let read, !Task.isCancelled, gen == detailGen else { return }
        detail = read.0
        if let checks = read.1 { self.checks = checks }
        closeReviewPanelIfGone()
    }

    /// Refresh: the list, and the open PR with it, threads included. What
    /// the user is writing (`drafts`) and the open box stay.
    func refresh() async {
        await load(force: true)
        if selected != nil { await loadDetail() }
    }

    /// CI of one commit for History's detail, `nil` when there's nothing to
    /// show: no recognised host, no token without asking, a commit the host
    /// doesn't have, or the request failed. Never touches the list's state
    /// (connect prompts, errors): this is a side lookup.
    func commitChecks(sha: String, force: Bool = false) async -> [CICheck]? {
        if !force, let cached = commitChecksCache[sha],
           Date().timeIntervalSince(cached.at) < Self.commitChecksTTL {
            return cached.checks
        }
        let resolvedHost: RemoteHost
        if let host {
            resolvedHost = host
        } else if let found = await resolveHost() {
            resolvedHost = found
        } else {
            return nil
        }
        let provider = makeProvider(resolvedHost)
        func token(rejected: String? = nil) async -> String? {
            if rejected == nil, let current = currentToken ?? silentToken { return current }
            guard case .token(let value) = await silentAuth(resolvedHost, rejected) else { return nil }
            silentToken = value
            return value
        }
        guard let first = await token() else { return nil }
        let checks: [CICheck]
        do {
            checks = try await provider.fetchCommitChecks(host: resolvedHost, sha: sha, token: first)
        } catch PullRequestFetchError.unauthorized {
            guard let fresh = await token(rejected: first),
                  let retried = try? await provider.fetchCommitChecks(host: resolvedHost, sha: sha, token: fresh) else {
                return nil
            }
            checks = retried
        } catch {
            return nil
        }
        if commitChecksCache.count >= Self.commitChecksCacheCap { commitChecksCache.removeAll() }
        commitChecksCache[sha] = (checks, Date())
        return checks
    }

    /// Drops everything (repo switch / teardown) and cancels the detail load.
    func reset() {
        closeDetail()
        listGen &+= 1
        ciTask?.cancel()
        items = []
        closedItems = []
        closedLoaded = false
        scope = .open
        currentUser = nil
        currentUserToken = nil
        pendingSelectionNumber = nil
        ciByPull = [:]
        host = nil
        error = nil
        requiresToken = false
        accountNotChosen = false
        connectInstanceId = nil
        reconnectAccountId = nil
        currentToken = nil
        silentToken = nil
        commitChecksCache = [:]
        lastLoadedAt = nil
        supportGen &+= 1
        requestChangesSupport = nil
        submittingReview = nil
        reviewSettlingPullId = nil
        drafts.removeAll()
        sendingDrafts = []
        resolvingThreadIds = []
        isMerging = false
    }

    /// The drafts stay: they're keyed by PR.
    private func clearDetail() {
        detail = nil
        commits = []
        files = []
        checks = []
        detailError = nil
        threadsGen &+= 1
        threads = []
        threadsHead = nil
        lineIndex = DiffLineIndex(parse: parsePatch)
        threadsError = nil
        isLoadingThreads = false
        composerTarget = nil
        replyingThreadId = nil
        focusRequest = nil
        filesDetail = nil
        reviewPanel = nil
    }

    private func placeThreads() {
        placedThreads = ThreadPlacement.place(threads, in: files, index: &lineIndex)
    }

    private func clearMerge() {
        mergeOptionsGen &+= 1
        mergeOptions = nil
        mergeOptionsError = nil
        isLoadingMergeOptions = false
        mergeDraft = nil
        keepsSelectionOutsideList = false
        mergeStatusRecheck?.cancel()
        mergeStatusRecheck = nil
    }

    private static func capture<T: Sendable>(_ block: @Sendable () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await block()) }
        catch { return .failure(error) }
    }

    /// A failed write's message after the PR it was on ("#42: …"), since
    /// its toast may show once another PR is on screen.
    static func naming(_ pull: PullRequest, on host: RemoteHost, _ message: String) -> String {
        String(localized: "\(host.provider.reference(pull.number)): \(message)",
               comment: "A failed action's message after the pull or merge request it was on, as in \"#42: …\"")
    }

    static func message(for error: Error) -> String {
        if let typed = error as? PullRequestFetchError {
            return typed.errorDescription ?? String(localized: "Request failed")
        }
        return error.localizedDescription
    }
}
