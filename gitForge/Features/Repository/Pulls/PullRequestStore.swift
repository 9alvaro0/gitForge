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
    var items: [PullRequest] = []
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
    var isLoadingDetail = false
    var detailError: String?
    /// Bumped by every detail op (`select` / `closeDetail` / `loadDetail`).
    /// The loader snapshots it on entry and drops its writes if it moved
    /// while awaiting — keeps a slow PR#1 fetch from landing on top of a
    /// freshly-selected PR#2 (or on a closed detail pane).
    var detailGen: UInt64 = 0
    /// Drives the spinner on "Resolve locally" while a try-merge runs.
    var localMergeRunning = false

    private let cli: GitCLI
    private let token: @MainActor (String) -> String?
    private var detailTask: Task<Void, Never>?

    /// - Parameter token: Keychain lookup by host; injectable for tests.
    init(cli: GitCLI,
         token: @escaping @MainActor (String) -> String? = { RemoteCredentialsStore.shared.token(for: $0) }) {
        self.cli = cli
        self.token = token
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

        guard let resolvedHost = await cli.remoteHost() else {
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

        let provider = PullRequestProviderFactory.make(for: resolvedHost)
        do {
            items = try await provider.fetchOpen(host: resolvedHost, token: token)
            lastLoadedAt = .now
        } catch {
            self.error = Self.message(for: error)
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

        let provider = PullRequestProviderFactory.make(for: host)
        let number = pr.number
        async let detailResult = Self.capture { try await provider.fetchDetail(host: host, number: number, token: token) }
        async let commitsResult = Self.capture { try await provider.fetchCommits(host: host, number: number, token: token) }
        async let filesResult = Self.capture { try await provider.fetchFiles(host: host, number: number, token: token) }
        let (detail, commits, files) = await (detailResult, commitsResult, filesResult)

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
    }

    /// Drops everything (repo switch / teardown) and cancels the detail load.
    func reset() {
        closeDetail()
        items = []
        host = nil
        error = nil
        requiresToken = false
        lastLoadedAt = nil
    }

    private func clearDetail() {
        detail = nil
        commits = []
        files = []
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
