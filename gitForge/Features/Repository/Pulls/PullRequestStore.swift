import Foundation
import Observation
import os

/// Pull / merge requests of the active repository: the open list and the
/// detail pane (overview, commits, files). Owned by `RepositoryViewModel`
/// (`viewModel.pullRequests`) but self-contained — it only needs the repo's
/// `GitCLI` to resolve the remote host, and `auth` for the token.
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
    var files: [PullRequestFileChange] = []
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

    // MARK: Review
    /// Whether the host takes "Request changes" (GitLab varies by version);
    /// read with each detail, kept across PRs of the same repo.
    var requestChangesSupport: RequestChangesSupport?
    /// The verdict being sent; disables the buttons meanwhile.
    var submittingReview: ReviewVerdict?
    /// What the user is typing in the review boxes (`ReviewDraftKey`).
    var drafts: [ReviewDraftKey: String] = [:]

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
    static var mergeStatusRecheckDelay: Duration = .seconds(3)

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
    ///   - auth: the token for a host (the repo's account); defaults to "connect".
    ///   - resolveHost / suggestInstance / makeProvider: default to the repo's
    ///     `origin` against the built-in instances and the real GitHub /
    ///     GitLab clients; tests pass fakes.
    init(cli: GitCLI,
         auth: (@MainActor (RemoteHost, String?) async -> PullRequestAuthResult)? = nil,
         silentAuth: (@MainActor (RemoteHost, String?) async -> PullRequestAuthResult)? = nil,
         resolveHost: (@MainActor () async -> RemoteHost?)? = nil,
         suggestInstance: (@MainActor () async -> InstanceSuggestion?)? = nil,
         makeProvider: @escaping @MainActor (RemoteHost) -> PullRequestProvider = { PullRequestProviderFactory.make(for: $0) },
         makeReviewProvider: @escaping @MainActor (RemoteHost) -> PullRequestReviewProvider = { PullRequestReviewProviderFactory.make(for: $0) }) {
        self.auth = auth ?? { _, _ in .connectAccount(instanceId: nil, replacing: nil) }
        self.silentAuth = silentAuth ?? auth ?? { _, _ in .connectAccount(instanceId: nil, replacing: nil) }
        self.resolveHost = resolveHost ?? { await cli.remoteHost(instances: HostingInstance.builtIns) }
        self.suggestInstance = suggestInstance ?? { nil }
        self.makeProvider = makeProvider
        self.makeReviewProvider = makeReviewProvider
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

        guard let resolvedHost = await resolveHost() else {
            host = nil
            items = []
            requiresToken = false
            suggestedInstance = await suggestInstance()
            return
        }
        suggestedInstance = nil
        host = resolvedHost
        Self.logger.info("Pulls: detected host \(resolvedHost.host, privacy: .public) (\(resolvedHost.provider.rawValue, privacy: .public))")

        guard var token = await authorize(resolvedHost) else {
            items = []
            currentToken = nil
            return
        }

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
        if currentUser == nil || currentUserToken != token {
            currentUser = try? await provider.fetchCurrentUser(host: resolvedHost, token: token)
            currentUserToken = currentUser == nil ? nil : token
        }
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

    /// The PR the list should open: the first row when nothing is selected
    /// or the selection left the list — unless it left because it was just
    /// merged here.
    func pullToAutoSelect() -> PullRequest? {
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
        guard let pr = selected, let host else { return }
        guard let token = currentToken else {
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
        let reviewProvider = makeReviewProvider(host)
        async let support = reviewProvider.requestChangesSupport(host: host, token: token)
        var (detail, commits, files, checks) = await fetchAll(token)
        // The token went bad since the list loaded: one fresh one, one retry.
        if case .failure(PullRequestFetchError.unauthorized) = detail,
           let fresh = await authorize(host, rejected: token) {
            currentToken = fresh
            (detail, commits, files, checks) = await fetchAll(fresh)
        }

        guard gen == detailGen else { return }
        switch detail {
        case .success(let value): self.detail = value
        case .failure(let error): detailError = Self.message(for: error)
        }
        switch commits {
        case .success(let value): self.commits = value
        case .failure(let error): if detailError == nil { detailError = Self.message(for: error) }
        }
        switch files {
        case .success(let value): self.files = value
        case .failure(let error): if detailError == nil { detailError = Self.message(for: error) }
        }
        // Checks are a nice-to-have: a failure leaves the tab empty rather
        // than flagging the whole detail.
        if case .success(let value) = checks { self.checks = value }
        let readSupport = await support
        if gen == detailGen { requestChangesSupport = readSupport }
        recheckMergeStatusIfComputing(gen: gen)
    }

    /// One more read of the detail alone, a moment later, while the host
    /// still works out an open PR's mergeability; dropped if the detail
    /// moved on meanwhile. It never schedules another, so it can't loop.
    private func recheckMergeStatusIfComputing(gen: UInt64) {
        guard gen == detailGen, let detail, detail.hostMergeStatus?.stillComputing == true,
              detail.pull.state == .open || detail.pull.state == .draft, let host else { return }
        let provider = makeProvider(host)
        let number = detail.pull.number
        mergeStatusRecheck = Task { [weak self] in
            try? await Task.sleep(for: Self.mergeStatusRecheckDelay)
            guard let self, !Task.isCancelled, self.detailGen == gen else { return }
            // The files, commits and checks already shown stay as they are.
            let fresh = try? await self.withToken(host) { token in
                try await provider.fetchDetail(host: host, number: number, token: token)
            }
            guard let fresh, !Task.isCancelled, self.detailGen == gen else { return }
            self.detail = fresh
        }
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
        requestChangesSupport = nil
        submittingReview = nil
        drafts = [:]
        isMerging = false
    }

    private func clearDetail() {
        detail = nil
        commits = []
        files = []
        checks = []
        detailError = nil
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

    static func message(for error: Error) -> String {
        if let typed = error as? PullRequestFetchError {
            return typed.errorDescription ?? String(localized: "Request failed")
        }
        return error.localizedDescription
    }
}
