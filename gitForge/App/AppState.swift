import Foundation
import Observation
import AppKit

/// Coordinator over the four sub-stores. Holds only flows that legitimately
/// touch more than one store (open/clone, bootstrap), plus the AppKit panels
/// that pick a directory or repo. Single-domain operations live on the
/// matching sub-store and views read those directly via `@Environment`.
@Observable
@MainActor
final class AppState {
    let catalog: RepositoryCatalog
    let gitEnvironment: GitEnvironment
    let clone: CloneController
    let ui: WorkspaceUI
    let profiles: ProfileStore
    let accounts: AccountStore
    let tokenRefresher: TokenRefresher
    let accountValidator: AccountValidator
    let accountConnector: AccountConnector
    let gitCredentials: AccountGitCredentials
    let accountChooser: AccountChooser
    let pullRequestAuth: AccountPullRequestAuth
    let network: NetworkMonitor

    init(
        catalog: RepositoryCatalog? = nil,
        gitEnvironment: GitEnvironment? = nil,
        clone: CloneController? = nil,
        ui: WorkspaceUI? = nil,
        profiles: ProfileStore? = nil,
        accounts: AccountStore? = nil,
        network: NetworkMonitor? = nil
    ) {
        // Default-arg expressions evaluate at the call site's isolation, but
        // `RepositoryCatalog`/etc. are `@MainActor`. Defer construction to the
        // body so the init's own `@MainActor` context covers the calls.
        self.catalog = catalog ?? RepositoryCatalog()
        self.gitEnvironment = gitEnvironment ?? GitEnvironment()
        self.clone = clone ?? CloneController()
        self.ui = ui ?? WorkspaceUI()
        let profileStore = profiles ?? ProfileStore()
        self.profiles = profileStore
        let accountStore = accounts ?? AccountStore()
        let refresher = TokenRefresher(secrets: accountStore.secrets, onRefreshRejected: { id in
            await accountStore.markNeedsAttention(id, .expired)
        })
        self.accounts = accountStore
        self.tokenRefresher = refresher
        self.accountValidator = AccountValidator(store: accountStore, refresher: refresher)
        self.accountConnector = AccountConnector(store: accountStore)
        let chooser = AccountChooser()
        self.accountChooser = chooser
        self.gitCredentials = AccountGitCredentials(store: accountStore, refresher: refresher, activeProfileId: { repoPath in
            let identity = await GitCLI(workingDirectory: URL(fileURLWithPath: repoPath)).currentIdentity()
            return await profileStore.match(for: identity)?.id
        }, chooseAccount: { remote in await chooser.choose(remote) })
        self.pullRequestAuth = AccountPullRequestAuth(store: accountStore, refresher: refresher, activeProfileId: { repoPath in
            let identity = await GitCLI(workingDirectory: URL(fileURLWithPath: repoPath)).currentIdentity()
            return await profileStore.match(for: identity)?.id
        }, chooseAccount: { remote in await chooser.choose(remote) })
        self.network = network ?? NetworkMonitor()
        self.catalog.gitCredentials = gitCredentials
        self.catalog.pullRequestAuth = pullRequestAuth
    }

    // MARK: - Bootstrap

    /// Spins up the app: probes git, reads global config, loads recents,
    /// reopens the last active repo, and starts the status poller.
    func bootstrap() async {
        async let gitCheck: Void = gitEnvironment.refreshGitInstallation()
        async let configRead: Void = gitEnvironment.refreshGlobalConfig()
        await catalog.load()
        _ = await gitCheck
        _ = await configRead

        // After the global config has landed, materialise it as a profile if
        // none exists yet. Onboarding handles the empty-config first-run case
        // by creating a profile alongside the global write; this seed covers
        // existing users who already had a `~/.gitconfig` before the app
        // learned about profiles.
        profiles.seedFromGlobalIfEmpty(gitEnvironment.globalConfig)

        if await catalog.restoreLastActive() {
            ui.workspaceSection = .history
        }
        catalog.startStatusPolling()

        // Hosting accounts: a last sync of the old per-host tokens into
        // accounts, then their old Keychain entries go; then check each account against
        // its API at most once a day, in the background. Last, so any
        // Keychain prompt comes after the window is restored.
        accounts.retireLegacyTokens(from: LegacyTokenKeychain())
        Task { await accountValidator.validateDueAccounts() }
    }

    // MARK: - Repository open / activate (cross-cutting: catalog + ui)

    /// Opens a repo and resets the workspace section to History when it's a
    /// switch from a different one. Throws on validation errors so callers
    /// can decide whether to surface them (the `activate` shortcut does).
    func openRepository(at url: URL) async throws {
        let isSwitching = try await catalog.open(at: url)
        if isSwitching {
            ui.workspaceSection = .history
        }
        // Cloud-sync folders rewrite `.git/` bytes out-of-band of git itself.
        // Warn once per open so silent corruption doesn't get blamed on the
        // app; only fires when the user actually switches repos so it
        // doesn't spam on every `activate` of an already-open repo.
        if isSwitching, let synced = SyncedFolderDetector.detect(in: catalog.activeRepository?.url ?? url) {
            ui.activeToast = ToastMessage(
                message: "Repository is inside \(synced.displayName) — sync conflicts on `.git/` can corrupt the repo. Consider moving it outside the synced folder.",
                kind: .warn
            )
        }
    }

    /// Convenience for the sidebar / Open Recent: opens the repo and surfaces
    /// any failure as a global alert.
    func activate(_ repository: Repository) async {
        do {
            try await openRepository(at: repository.url)
        } catch {
            ui.presentedError = PresentedError(error: error)
        }
    }

    // MARK: - Clone (cross-cutting: clone + catalog + ui)

    /// Clones `url` into `path` (with optional `~` expansion) and opens the
    /// resulting repository when it finishes. Fire-and-forget — observe
    /// `clone.cloneState` for progress; call `clone.cancel()` to abort.
    /// `accountId`: the account "My repos" listed the repo with; it signs
    /// the clone and stays the repo's account. `profileId`: the identity
    /// profile pinned to the new repo (`nil` keeps the global identity).
    func startClone(url: String, path: String, branch: String?, accountId: UUID? = nil, profileId: UUID? = nil) {
        clone.start { [weak self] in
            await self?.runClone(url: url, path: path, branch: branch, accountId: accountId, profileId: profileId)
        }
    }

    /// Pins `profileId`'s identity to the active repo (the one just cloned).
    /// A failure doesn't undo the clone; a warning toast says so and the
    /// result is `false`, so the caller doesn't cover it with "Cloned".
    @discardableResult
    func applyCloneProfile(_ profileId: UUID?) async -> Bool {
        guard let profileId, let profile = profiles.profiles.first(where: { $0.id == profileId }),
              let viewModel = catalog.activeViewModel else { return true }
        do {
            try await viewModel.applyProfile(profile)
            return true
        } catch {
            ui.activeToast = ToastMessage(message: "Cloned, but couldn't apply \(profile.name): \(error.userMessage)", kind: .warn)
            return false
        }
    }

    private func runClone(url: String, path: String, branch: String?, accountId: UUID?, profileId: UUID?) async {
        let trimmedUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUrl.isEmpty, !trimmedPath.isEmpty else {
            ui.presentedError = PresentedError(title: "Clone failed", message: "Source URL and local path are required.")
            return
        }
        let expanded = (trimmedPath as NSString).expandingTildeInPath
        let destination = URL(fileURLWithPath: expanded)
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            ui.presentedError = PresentedError(title: "Clone failed", message: "Destination already exists: \(expanded)")
            return
        }

        var pin = CloneAccountPin.pin(accountId, destination: destination, in: accounts)
        clone.cloneState = .running(stage: "Connecting…", percent: 0)
        defer { clone.cloneState = .idle }

        do {
            try await GitCLI.clone(
                url: trimmedUrl,
                destination: destination,
                branch: branch,
                credentials: gitCredentials,
                onProgress: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        // Progress hops are unordered relative to this
                        // function's own continuation: a late tick must not
                        // flip a finished (idle) clone back to "running".
                        guard let self, self.clone.cloneState.isRunning else { return }
                        self.clone.cloneState = .running(stage: progress.stage, percent: progress.percent)
                    }
                }
            )
        } catch is CancellationError {
            pin?.undo()
            Self.cleanupPartialClone(at: destination)
            ui.activeToast = ToastMessage(message: "Clone cancelled", kind: .info)
            return
        } catch {
            pin?.undo()
            Self.cleanupPartialClone(at: destination)
            ui.presentedError = PresentedError(error: error, title: "Clone failed")
            return
        }

        // The clone is complete on disk from here on. A failure (or a late
        // cancel) while opening it must never trash it — the previous single
        // do/catch sent a finished clone to the Trash when Cancel landed
        // during `openRepository`.
        // Before opening, so the new repo is signed with the pinned account
        // from its first fetch, and never re-keyed onto another repo that
        // became active meanwhile.
        await pin?.followRepositoryRoot()
        do {
            try await openRepository(at: destination)
            let profileApplied = await applyCloneProfile(profileId)
            ui.workspaceSection = .history
            if profileApplied {
                ui.activeToast = ToastMessage(message: "Cloned \(destination.lastPathComponent)", kind: .ok)
            }
        } catch {
            ui.presentedError = PresentedError(
                title: "Cloned, but couldn't open it",
                message: "\(destination.path(percentEncoded: false)) — \(error.userMessage)"
            )
        }
    }

    /// Only deletes if the directory contains a `.git` entry — guards against
    /// a TOCTOU where the user materialised the path between the pre-flight
    /// existence check and git starting. Uses Trash so a misfire is recoverable.
    static func cleanupPartialClone(at destination: URL) {
        let fm = FileManager.default
        let gitDir = destination.appendingPathComponent(".git").path(percentEncoded: false)
        guard fm.fileExists(atPath: gitDir) else { return }
        _ = try? fm.trashItem(at: destination, resultingItemURL: nil)
    }

    // MARK: - AppKit pickers (UI helpers that result in opening a repo)

    /// Opens an `NSOpenPanel` and returns the chosen directory's path. Used
    /// by the Clone view to pick a parent directory.
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

    /// Open Repository menu / sidebar entry. Picks a folder, opens it as a
    /// repo, and surfaces any failure.
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
            ui.presentedError = PresentedError(error: error)
        }
    }
}
