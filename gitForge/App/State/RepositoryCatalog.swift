import Foundation

/// Catalog of known repositories, the one currently active, its live VM, and
/// the per-repo lightweight status snapshots used by the sidebar pills. Owns
/// the on-disk recents store, the "last active repo" key, and the background
/// poller that keeps the snapshots close to the truth.
@Observable
@MainActor
final class RepositoryCatalog {
    var repositories: [Repository] = []
    var activeRepository: Repository?
    var activeViewModel: RepositoryViewModel?
    var repositoryStatuses: [URL: RepoStatusSnapshot] = [:]

    private let store = RepositoryStore()
    private var statusPollTask: Task<Void, Never>?
    private static let statusPollInterval: Duration = .seconds(30)
    private static let lastActiveRepoKey = "lastActiveRepositoryPath"

    // MARK: - Persistence / lifecycle

    /// Loads the persisted recents list. Call once at bootstrap.
    func load() async {
        await store.load()
        repositories = await store.repositories
    }

    /// Validates that `url` is a real git repo, marks it as recently opened,
    /// makes it active (creating a fresh VM if needed), and persists the
    /// "last active repo" key. Returns whether this was a switch from a
    /// different repo — callers use it to decide whether to reset UI like the
    /// workspace section.
    @discardableResult
    func open(at url: URL) async throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw RepositoryError.directoryNotFound(url)
        }
        guard let resolved = await GitCLI.resolveRepositoryRoot(at: url) else {
            throw RepositoryError.notAGitRepository(url)
        }
        // Normalise to the worktree toplevel — `rev-parse` happily accepts a
        // subdirectory, but operations that build absolute paths from
        // `git ls-files` output assume `workingDirectory` is the root.
        let url = resolved
        let isSwitching = activeRepository?.url != url
        repositories = await store.touch(url)
        let active = repositories.first { $0.url == url }
        activeRepository = active
        if let active, activeViewModel?.repository.url != active.url {
            // Tear down the previous VM's timers/observers before replacing it
            // — otherwise its background work keeps running until ARC happens
            // to release it, which is never guaranteed.
            activeViewModel?.stopReactivity()
            activeViewModel = RepositoryViewModel(repository: active)
        }
        UserDefaults.standard.set(url.path(percentEncoded: false), forKey: Self.lastActiveRepoKey)
        // Seed the snapshot for any newly added repo so the sidebar pills
        // reflect reality before the next poll tick fires.
        await refreshRepoStatus(url)
        return isSwitching
    }

    /// Closes the active repository: stops its VM's timers, clears the slot,
    /// and forgets the "last active" key so a relaunch lands on Welcome.
    func close() {
        activeViewModel?.stopReactivity()
        activeRepository = nil
        activeViewModel = nil
        UserDefaults.standard.removeObject(forKey: Self.lastActiveRepoKey)
    }

    /// Removes `url` from recents and drops its cached snapshot. If it was
    /// the active repo, also tears down the VM and clears "last active".
    func remove(_ url: URL) async {
        repositories = await store.remove(url)
        repositoryStatuses.removeValue(forKey: url)
        if activeRepository?.url == url {
            close()
        }
    }

    /// Reopens whichever repo was active at the last quit. Silently returns
    /// `false` if the saved path is gone, no longer a git repo, or never set
    /// — the user just lands on Welcome instead of seeing an error.
    @discardableResult
    func restoreLastActive() async -> Bool {
        guard let path = UserDefaults.standard.string(forKey: Self.lastActiveRepoKey) else { return false }
        let url = URL(fileURLWithPath: path)
        return (try? await open(at: url)) != nil
    }

    // MARK: - Status polling

    /// Starts the 30s background poller. Cheap calls per repo (status,
    /// ahead/behind against cached upstream); no `git fetch`.
    func startStatusPolling() {
        statusPollTask?.cancel()
        statusPollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAllRepoStatuses()
                try? await Task.sleep(for: Self.statusPollInterval)
            }
        }
    }

    /// Stops the poller. Idempotent.
    func stopStatusPolling() {
        statusPollTask?.cancel()
        statusPollTask = nil
    }

    func refreshAllRepoStatuses() async {
        // Skip the active repo: its VM is already exercising `.git/index.lock`
        // and a parallel `git status` from here can collide with it. Mirror
        // the VM's live state into the cache instead, so the pill stays fresh
        // for when the user switches away.
        let activeUrl = activeRepository?.url
        let urls = repositories.map(\.url).filter { $0 != activeUrl }
        await withTaskGroup(of: (URL, RepoStatusSnapshot?).self) { group in
            for url in urls {
                group.addTask { (url, await Self.snapshot(for: url)) }
            }
            for await (url, snapshot) in group {
                if let snapshot { repositoryStatuses[url] = snapshot }
            }
        }
        if let activeUrl, let vm = activeViewModel, vm.hasLoadedStatusOnce {
            repositoryStatuses[activeUrl] = RepoStatusSnapshot(
                branch: vm.currentBranchName,
                dirty: vm.status.files.count,
                ahead: vm.aheadCount,
                behind: vm.behindCount
            )
        }
        // Drop snapshots for repos that aren't in the list anymore — keeps the
        // dictionary from accumulating ghost entries over the app's lifetime.
        let live = Set(repositories.map(\.url))
        repositoryStatuses = repositoryStatuses.filter { live.contains($0.key) }
    }

    func refreshRepoStatus(_ url: URL) async {
        if let snapshot = await Self.snapshot(for: url) {
            repositoryStatuses[url] = snapshot
        }
    }

    private static func snapshot(for url: URL) async -> RepoStatusSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        let cli = GitCLI(workingDirectory: url)
        let branch = await cli.currentBranchName()
        let dirty = (try? await cli.status())?.files.count ?? 0
        var ahead = 0
        var behind = 0
        if let branch, let upstream = await cli.upstreamName(),
           let counts = try? await cli.aheadBehind(branch: branch, upstream: upstream) {
            ahead = counts.ahead
            behind = counts.behind
        }
        return RepoStatusSnapshot(branch: branch, dirty: dirty, ahead: ahead, behind: behind)
    }
}
