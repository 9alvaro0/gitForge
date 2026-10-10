import Foundation
import Observation
import os

/// Pull / merge requests of the active repository: the open list and the
/// detail pane (overview, commits, files). Owned by `RepositoryViewModel`
/// (`viewModel.pullRequests`) but self-contained — it only needs the repo's
/// `GitCLI` to resolve the remote host, and the Keychain for the token.
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
    /// CI summary per PR id, filled in after the list loads.
    var ciByPull: [String: CIStatus] = [:]
    var host: RemoteHost?
    var isLoading = false
    var error: String?
    /// Host detected but no token configured — drives the "Connect a host"
    /// empty state in `PullsView`.
    var requiresToken = false
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

    private let token: @MainActor (String) -> String?
    private let resolveHost: @MainActor () async -> RemoteHost?
    private let makeProvider: @MainActor (RemoteHost) -> PullRequestProvider
    private var detailTask: Task<Void, Never>?
    private var ciTask: Task<Void, Never>?
    /// Bumped by every list load so a slow CI fill for an older list drops
    /// its writes.
    private var listGen: UInt64 = 0
    /// How many CI lookups run at once while filling the list.
    static let ciConcurrency = 6

    /// - Parameters:
    ///   - token: Keychain lookup by host; injectable for tests.
    ///   - resolveHost / makeProvider: default to the repo's `origin` and the
    ///     real GitHub / GitLab clients; tests pass fakes.
    init(cli: GitCLI,
         token: @escaping @MainActor (String) -> String? = { RemoteCredentialsStore.shared.token(for: $0) },
         resolveHost: (@MainActor () async -> RemoteHost?)? = nil,
         makeProvider: @escaping @MainActor (RemoteHost) -> PullRequestProvider = { PullRequestProviderFactory.make(for: $0) }) {
        self.token = token
        self.resolveHost = resolveHost ?? { await cli.remoteHost() }
        self.makeProvider = makeProvider
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
        guard let host, let token = token(host.host), !isLoadingClosed else { return }
        isLoadingClosed = true
        defer { isLoadingClosed = false }
        let gen = listGen
        do {
            let closed = try await makeProvider(host).fetchPulls(host: host, state: .closed, token: token)
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
    /// 1) detect the remote host (`origin`); stop if not GitHub/GitLab
    /// 2) read the token; surface "needs token" if missing
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
            return
        }
        host = resolvedHost
        Self.logger.info("Pulls: detected host \(resolvedHost.host, privacy: .public) (\(resolvedHost.provider.rawValue, privacy: .public))")

        guard let token = token(resolvedHost.host) else {
            items = []
            requiresToken = true
            Self.logger.info("Pulls: no token for host \(resolvedHost.host, privacy: .public)")
            return
        }
        requiresToken = false

        let provider = makeProvider(resolvedHost)
        do {
            items = try await provider.fetchPulls(host: resolvedHost, state: .open, token: token)
            lastLoadedAt = .now
        } catch {
            self.error = Self.message(for: error)
            return
        }
        // The closed list is refetched next time it's shown.
        closedLoaded = false
        closedItems = []
        if currentUser == nil {
            currentUser = try? await provider.fetchCurrentUser(host: resolvedHost, token: token)
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
    }

    /// Fetch the three detail payloads in parallel. The first failure wins
    /// `detailError`; successful parts still render.
    func loadDetail() async {
        detailGen &+= 1
        let gen = detailGen
        guard let pr = selected, let host else { return }
        guard let token = token(host.host) else {
            detailError = "No token configured for \(host.host)."
            return
        }

        isLoadingDetail = true
        detailError = nil
        defer { if gen == detailGen { isLoadingDetail = false } }

        let provider = makeProvider(host)
        let number = pr.number
        async let detailResult = Self.capture { try await provider.fetchDetail(host: host, number: number, token: token) }
        async let commitsResult = Self.capture { try await provider.fetchCommits(host: host, number: number, token: token) }
        async let filesResult = Self.capture { try await provider.fetchFiles(host: host, number: number, token: token) }
        async let checksResult = Self.capture { try await provider.fetchChecks(host: host, pull: pr, token: token) }
        let (detail, commits, files, checks) = await (detailResult, commitsResult, filesResult, checksResult)

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
        ciByPull = [:]
        host = nil
        error = nil
        requiresToken = false
        lastLoadedAt = nil
    }

    private func clearDetail() {
        detail = nil
        commits = []
        files = []
        checks = []
        detailError = nil
    }

    private static func capture<T: Sendable>(_ block: @Sendable () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await block()) }
        catch { return .failure(error) }
    }

    private static func message(for error: Error) -> String {
        if let typed = error as? PullRequestFetchError {
            return typed.errorDescription ?? "Request failed"
        }
        return error.localizedDescription
    }
}
