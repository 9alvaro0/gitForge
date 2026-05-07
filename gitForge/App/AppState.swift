import Foundation
import Observation
import AppKit

enum GitInstallationStatus: Sendable, Equatable {
    case checking
    case available
    case notFound
}

@Observable
@MainActor
final class AppState {
    var gitStatus: GitInstallationStatus = .checking
    var repositories: [Repository] = []
    var activeRepository: Repository?
    var activeViewModel: RepositoryViewModel?
    var presentedError: PresentedError?

    /// Flags driven by global menu commands. Views observe these and present
    /// the matching sheet/alert; menus only flip the bool.
    var newBranchSheetVisible: Bool = false
    var discardAllConfirmVisible: Bool = false

    // Redesigned UI state.
    var workspaceSection: WorkspaceSection = .history
    var theme: AppTheme = AppTheme()
    var commandPaletteOpen: Bool = false
    var activeToast: ToastMessage?

    /// Snapshot of `git config --global` — identity, signing key, etc.
    var globalConfig: GitGlobalConfig = .unknown

    /// Per-repo branch + dirty + ahead/behind, refreshed in the background so
    /// every row in the sidebar reflects the truth, not just the active one.
    var repositoryStatuses: [URL: RepoStatusSnapshot] = [:]

    private let store = RepositoryStore()
    private let configReader = GitGlobalConfigReader.shared
    private var statusPollTask: Task<Void, Never>?
    private static let statusPollInterval: UInt64 = 30_000_000_000   // 30s

    func bootstrap() async {
        async let gitCheck: Void = refreshGitInstallation()
        async let configRead: GitGlobalConfig = configReader.read()
        await store.load()
        repositories = await store.repositories
        _ = await gitCheck
        globalConfig = await configRead

        // Make cached emoji shortcodes available before the first PR detail
        // render, then refresh in the background.
        EmojiShortcodeStore.shared.loadCachedSync()
        Task { await EmojiShortcodeStore.shared.refreshIfNeeded() }

        startStatusPolling()
    }

    /// Loops in the background, refreshing every repo's lightweight status
    /// snapshot so the sidebar pills are always close to the truth — without
    /// needing per-repo filesystem watchers. Cheap calls (status, ahead/behind
    /// against cached upstream); no `git fetch`.
    private func startStatusPolling() {
        statusPollTask?.cancel()
        statusPollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAllRepoStatuses()
                try? await Task.sleep(nanoseconds: Self.statusPollInterval)
            }
        }
    }

    func refreshAllRepoStatuses() async {
        let urls = repositories.map(\.url)
        await withTaskGroup(of: (URL, RepoStatusSnapshot?).self) { group in
            for url in urls {
                group.addTask { (url, await Self.snapshot(for: url)) }
            }
            for await (url, snapshot) in group {
                if let snapshot { repositoryStatuses[url] = snapshot }
            }
        }
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

    func refreshGlobalConfig() async {
        globalConfig = await configReader.read()
    }

    func updateIdentity(name: String? = nil, email: String? = nil) async {
        do {
            if let name { try await configReader.setName(name) }
            if let email { try await configReader.setEmail(email) }
            await refreshGlobalConfig()
        } catch {
            presentedError = PresentedError(error: error, title: "Couldn’t update git identity")
        }
    }

    func updateSigningKey(_ key: String?) async {
        await applyConfigChange(title: "Couldn't update signing key") {
            try await self.configReader.setSigningKey(key)
        }
    }

    func updateDefaultBranch(_ name: String?) async {
        await applyConfigChange(title: "Couldn't update default branch") {
            try await self.configReader.setDefaultBranch(name)
        }
    }

    func updatePullStrategy(_ strategy: String?) async {
        await applyConfigChange(title: "Couldn't update pull strategy") {
            try await self.configReader.setPullStrategy(strategy)
        }
    }

    /// Updates the auto-fetch interval and immediately restarts the timer on
    /// the active repo so the user doesn't have to relaunch the app.
    func updateAutoFetchInterval(_ seconds: Int?) async {
        await applyConfigChange(title: "Couldn't update auto-fetch") {
            try await self.configReader.setAutoFetchInterval(seconds)
        }
        // Restart the timer with the new interval.
        activeViewModel?.startReactivity(autoFetchIntervalSeconds: seconds ?? 0)
    }

    private func applyConfigChange(title: String, _ block: () async throws -> Void) async {
        do {
            try await block()
            await refreshGlobalConfig()
        } catch {
            presentedError = PresentedError(error: error, title: title)
        }
    }

    /// Live state of the clone operation. Drives the progress bar and the
    /// "Clone vs Cancel" button label in `CloneView`.
    enum CloneState: Sendable, Equatable {
        case idle
        case running(stage: String, percent: Double)
    }
    var cloneState: CloneState = .idle
    var isCloning: Bool {
        if case .running = cloneState { return true }
        return false
    }

    private var cloneTask: Task<Void, Never>?

    /// Clones `url` into `path` (with optional `~` expansion) and opens the
    /// resulting repository when it finishes. Errors surface via `presentedError`.
    /// Fire-and-forget — observe `cloneState` for progress; call `cancelClone()`
    /// to abort.
    func startClone(url: String, path: String, branch: String?) {
        cloneTask?.cancel()
        cloneTask = Task { [weak self] in
            await self?.runClone(url: url, path: path, branch: branch)
        }
    }

    func cancelClone() {
        cloneTask?.cancel()
    }

    private func runClone(url: String, path: String, branch: String?) async {
        let trimmedUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUrl.isEmpty, !trimmedPath.isEmpty else {
            presentedError = PresentedError(title: "Clone failed", message: "Source URL and local path are required.")
            return
        }
        let expanded = (trimmedPath as NSString).expandingTildeInPath
        let destination = URL(fileURLWithPath: expanded)
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            presentedError = PresentedError(title: "Clone failed", message: "Destination already exists: \(expanded)")
            return
        }

        cloneState = .running(stage: "Connecting…", percent: 0)
        defer {
            cloneState = .idle
            cloneTask = nil
        }

        do {
            try await GitCLI.clone(
                url: trimmedUrl,
                destination: destination,
                branch: branch,
                onProgress: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.cloneState = .running(stage: progress.stage, percent: progress.percent)
                    }
                }
            )
            try await openRepository(at: destination)
            workspaceSection = .history
            activeToast = ToastMessage(message: "Cloned \(destination.lastPathComponent)", kind: .ok)
        } catch is CancellationError {
            // User-initiated cancel: clean up the partial directory git left
            // behind so the next attempt with the same path doesn't hit the
            // "destination exists" guard.
            try? FileManager.default.removeItem(at: destination)
            activeToast = ToastMessage(message: "Clone cancelled", kind: .info)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            presentedError = PresentedError(error: error, title: "Clone failed")
        }
    }

    func refreshGitInstallation() async {
        if gitStatus != .checking {
            gitStatus = .checking
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["GITFORGE_FAKE_NO_GIT"] != nil {
            gitStatus = .notFound
            return
        }
        #endif
        let isAvailable = await GitCLI.isGitAvailable()
        gitStatus = isAvailable ? .available : .notFound
    }

    func openRepository(at url: URL) async throws {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw RepositoryError.directoryNotFound(url)
        }
        guard await GitCLI.isGitRepository(at: url) else {
            throw RepositoryError.notAGitRepository(url)
        }
        let isSwitchingRepo = activeRepository?.url != url
        repositories = await store.touch(url)
        let active = repositories.first { $0.url == url }
        activeRepository = active
        if let active, activeViewModel?.repository.url != active.url {
            activeViewModel = RepositoryViewModel(repository: active)
        }
        // Always land on History when entering a different repo — fresh
        // context, fresh starting point. No-op when re-touching the same one
        // so the user doesn't get yanked out of Settings/Branches/etc.
        if isSwitchingRepo {
            workspaceSection = .history
        }
        // Seed the snapshot for any newly added repo so the sidebar pills
        // reflect reality before the next poll tick fires.
        await refreshRepoStatus(url)
    }

    func activate(_ repository: Repository) async {
        do {
            try await openRepository(at: repository.url)
        } catch {
            presentedError = PresentedError(error: error)
        }
    }

    func closeRepository() {
        activeRepository = nil
        activeViewModel = nil
    }

    func removeFromRecents(_ url: URL) async {
        repositories = await store.remove(url)
        if activeRepository?.url == url {
            activeRepository = nil
            activeViewModel = nil
        }
    }

    /// Opens an `NSOpenPanel` and returns the chosen directory's path.
    /// Used by the Clone view to pick a parent directory.
    func pickDirectoryPath(prompt: String = "Choose") async -> String? {
        let panel = NSOpenPanel()
        panel.title = prompt
        panel.prompt = prompt
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path(percentEncoded: false)
    }

    func presentOpenRepositoryPanel() async {
        let panel = NSOpenPanel()
        panel.title = "Open Repository"
        panel.prompt = "Open"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try await openRepository(at: url)
        } catch {
            presentedError = PresentedError(error: error)
        }
    }
}

struct PresentedError: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let message: String

    init(title: String = "Couldn’t open repository", message: String) {
        self.title = title
        self.message = message
    }

    init(error: Error, title: String = "Couldn’t open repository") {
        self.title = title
        self.message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
