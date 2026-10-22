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
    /// The Reviews inbox: the open pull requests of the repos the user follows.
    let reviews: ReviewsStore
    /// The identity profile a repository (or a clone in progress) uses.
    let profileLookup: ActiveProfileLookup
    let network: NetworkMonitor
    /// The What's New sheet shown after an update and from the Help menu.
    let whatsNew: WhatsNewController

    init(
        catalog: RepositoryCatalog? = nil,
        gitEnvironment: GitEnvironment? = nil,
        clone: CloneController? = nil,
        ui: WorkspaceUI? = nil,
        profiles: ProfileStore? = nil,
        accounts: AccountStore? = nil,
        network: NetworkMonitor? = nil,
        whatsNew: WhatsNewController? = nil,
        reviewsSnapshots: ReviewsSnapshotStore? = nil
    ) {
        // Default-arg expressions evaluate at the call site's isolation, but
        // `RepositoryCatalog`/etc. are `@MainActor`. Defer construction to the
        // body so the init's own `@MainActor` context covers the calls.
        self.catalog = catalog ?? RepositoryCatalog()
        self.gitEnvironment = gitEnvironment ?? GitEnvironment()
        self.clone = clone ?? CloneController()
        self.ui = ui ?? WorkspaceUI()
        self.whatsNew = whatsNew ?? WhatsNewController()
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
        let profileLookup = ActiveProfileLookup(profiles: profileStore)
        self.profileLookup = profileLookup
        let activeProfileId: @Sendable (String) async -> UUID? = { await profileLookup.profileId(forRepoAt: $0) }
        self.gitCredentials = AccountGitCredentials(store: accountStore, refresher: refresher, activeProfileId: activeProfileId,
                                                    chooseAccount: { remote in await chooser.choose(remote) })
        let requestAuth = AccountPullRequestAuth(store: accountStore, refresher: refresher, activeProfileId: activeProfileId,
                                                 chooseAccount: { remote in await chooser.choose(remote) })
        self.pullRequestAuth = requestAuth
        self.network = network ?? NetworkMonitor()
        // `localRemotesForReviews` needs `self`, which can't be captured until
        // every property is set: the environment reaches it through a weak
        // reference that is filled in last. The other closures hold the
        // sub-stores, not `self`.
        let owner = WeakAppState()
        self.reviews = ReviewsStore(environment: ReviewsEnvironment(
            accounts: { Self.reviewsAccounts(in: accountStore) },
            localRemotes: { await owner.appState?.localRemotesForReviews() ?? [] },
            token: { id, rejected in await requestAuth.access(accountId: id, rejected: rejected) },
            makeProvider: { PullRequestProviderFactory.make(for: $0) },
            makeBrowser: { RemoteRepoBrowserFactory.make(for: $0) },
            makeActivity: { ReviewActivitySourceFactory.make(for: $0) },
            snapshots: reviewsSnapshots ?? ReviewsSnapshotStore()
        ))
        self.catalog.gitCredentials = gitCredentials
        self.catalog.pullRequestAuth = pullRequestAuth
        owner.appState = self
    }

    // MARK: - Reviews inbox

    /// A weak reference to the `AppState` still being built, for the closures
    /// of the Reviews environment.
    @MainActor
    private final class WeakAppState {
        weak var appState: AppState?
    }

    /// Most `origin` reads at once: one cheap `git` process each, so a long
    /// catalog doesn't spawn them all together.
    private static let remoteReadConcurrency = 8

    /// The accounts the inbox reads with, with their instance, in
    /// `AccountStore.accounts` order: those that sign, and those to reconnect
    /// (their repos keep the pull requests they have until they're connected
    /// again). An unverified one isn't asked for anything.
    private static func reviewsAccounts(in store: AccountStore) -> [(account: HostingAccount, instance: HostingInstance)] {
        store.accounts.compactMap { account in
            let toReconnect: Bool
            if case .needsAttention = account.status { toReconnect = true } else { toReconnect = false }
            guard toReconnect || AccountGitCredentials.signs(account),
                  let instance = store.instances.first(where: { $0.id == account.instanceId }) else { return nil }
            return (account, instance)
        }
    }

    /// The catalog's clones whose `origin` is on a declared instance, in the
    /// catalog's order. Each comes with the account its own Pull requests
    /// screen reads it with (`AccountPullRequestAuth.resolution`, with the
    /// clone's identity profile), or none when several fit; nobody is asked.
    /// A clone without an `origin`, or on an undeclared host, gives nothing.
    func localRemotesForReviews() async -> [LocalRemote] {
        let instances = accounts.instances
        let clones = catalog.repositories
        let profileLookup = profileLookup
        let auth = pullRequestAuth
        return await withTaskGroup(of: (index: Int, remote: LocalRemote?).self) { group in
            func read(_ index: Int) {
                let repository = clones[index]
                group.addTask {
                    guard let url = await GitCLI(workingDirectory: repository.url).remoteURL("origin"),
                          let host = RemoteHost.parse(url, instances: instances) else { return (index, nil) }
                    let profile = await profileLookup.profileId(forRepoAt: repository.path)
                    let resolution = await auth.resolution(host: host, repoPath: repository.path, activeProfileId: profile)
                    let accountId: UUID? = if case .account(let account) = resolution { account.id } else { nil }
                    return (index, LocalRemote(host: host, repository: repository, assignedAccountId: accountId))
                }
            }
            var next = 0
            while next < min(Self.remoteReadConcurrency, clones.count) {
                read(next)
                next += 1
            }
            var found: [(index: Int, remote: LocalRemote)] = []
            for await result in group {
                if let remote = result.remote { found.append((result.index, remote)) }
                if next < clones.count {
                    read(next)
                    next += 1
                }
            }
            return found.sorted { $0.index < $1.index }.map(\.remote)
        }
    }

    // MARK: - Bootstrap

    /// Spins up the app: probes git, reads global config, loads recents,
    /// reopens the last active repo, and starts the status poller.
    func bootstrap() async {
        async let gitCheck: Void = gitEnvironment.refreshGitInstallation()
        async let configRead: Void = gitEnvironment.refreshGlobalConfig()
        await catalog.load()
        // Before anything can refresh the inbox: the snapshot replaces what's
        // live.
        reviews.loadSnapshot()
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

        // The Reviews inbox: read once now, then every few minutes while the
        // app is online and in front. Last, so the accounts are settled.
        Task { await reviews.refresh(force: true) }
        reviews.startAutoRefresh(isOnline: { [network] in network.isOnline }, isActive: { NSApp.isActive })
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
                message: String(localized: "Repository is inside \(synced.displayName) — sync conflicts on `.git/` can corrupt the repo. Consider moving it outside the synced folder."),
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

    /// "Open in repository" from Reviews (R1 Ruling 13): activates the clone
    /// at `url`, goes to its Pull requests and opens `number` there, now if
    /// its list shows it, else once it does. The inbox only lists open pull
    /// requests, so the list goes back to Open: a repository already open on
    /// Mine or Closed would otherwise keep its selection and jump to the pull
    /// request only when Open is picked later. A clone that can't be opened
    /// shows why and leaves the section as it was.
    func openPullRequest(number: Int, inRepositoryAt url: URL) async {
        do {
            try await openRepository(at: url)
        } catch {
            ui.presentedError = PresentedError(error: error)
            return
        }
        ui.workspaceSection = .pulls
        guard let pulls = catalog.activeViewModel?.pullRequests else { return }
        if pulls.scope != .open { await pulls.setScope(.open) }
        pulls.requestSelection(number: number)
    }

    // MARK: - Clone (cross-cutting: clone + catalog + ui)

    /// Clones `url` into `path` (with optional `~` expansion) and opens the
    /// resulting repository when it finishes. Fire-and-forget — observe
    /// `clone.cloneState` for progress; call `clone.cancel()` to abort.
    /// `accountId`: the account "My repos" listed the repo with; it signs
    /// the clone and stays the repo's account. `profileId`: the identity
    /// profile pinned to the new repo (`nil` keeps the global identity).
    func startClone(url: String, path: String, branch: String?, options: CloneOptions = CloneOptions(),
                    accountId: UUID? = nil, profileId: UUID? = nil) {
        clone.start { [weak self] in
            await self?.runClone(url: url, path: path, branch: branch, options: options,
                                 accountId: accountId, profileId: profileId)
        }
    }

    /// Pins `profileId`'s identity to the active repo (the one just cloned).
    /// A failure doesn't undo the clone; a warning toast says so and the
    /// result is `false`, so the caller doesn't cover it with "Cloned".
    @discardableResult
    func applyCloneProfile(_ profileId: UUID?) async -> Bool {
        guard let profileId, let viewModel = catalog.activeViewModel else { return true }
        guard let profile = profiles.profiles.first(where: { $0.id == profileId }) else {
            ui.activeToast = ToastMessage(message: String(localized: "Cloned, but the chosen profile no longer exists"), kind: .warn)
            return false
        }
        do {
            try await viewModel.applyProfile(profile)
            return true
        } catch {
            ui.activeToast = ToastMessage(message: String(localized: "Cloned, but couldn't apply \(profile.name): \(error.userMessage)"), kind: .warn)
            return false
        }
    }

    private func runClone(url: String, path: String, branch: String?, options: CloneOptions,
                          accountId: UUID?, profileId: UUID?) async {
        let trimmedUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUrl.isEmpty, !trimmedPath.isEmpty else {
            ui.presentedError = PresentedError(title: String(localized: "Clone failed"), message: String(localized: "Source URL and local path are required."))
            return
        }
        let expanded = (trimmedPath as NSString).expandingTildeInPath
        let destination = URL(fileURLWithPath: expanded)
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            ui.presentedError = PresentedError(title: String(localized: "Clone failed"), message: String(localized: "Destination already exists: \(expanded)"))
            return
        }

        var pin = CloneAccountPin.pin(accountId, destination: destination, in: accounts)
        let destinationPath = destination.path(percentEncoded: false)
        profileLookup.beginClone(at: destinationPath, profileId: profileId)
        clone.cloneState = .running(stage: String(localized: "Connecting…"), percent: 0)
        defer {
            clone.cloneState = .idle
            profileLookup.endClone(at: destinationPath)
        }

        do {
            try await GitCLI.clone(
                url: trimmedUrl,
                destination: destination,
                branch: branch,
                options: options,
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
            ui.activeToast = ToastMessage(message: String(localized: "Clone cancelled"), kind: .info)
            return
        } catch {
            pin?.undo()
            Self.cleanupPartialClone(at: destination)
            ui.presentedError = PresentedError(error: error, title: String(localized: "Clone failed"))
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
                ui.activeToast = ToastMessage(message: String(localized: "Cloned \(destination.lastPathComponent)"), kind: .ok)
            }
        } catch {
            ui.presentedError = PresentedError(
                title: String(localized: "Cloned, but couldn't open it"),
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
    func pickDirectoryPath(prompt: String = String(localized: "Choose")) async -> String? {
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

    /// File ▸ New Repository… and Welcome: picks (or creates) a folder, runs
    /// `git init` there unless it already holds a repository, and opens it.
    func presentNewRepositoryPanel() async {
        guard let path = await pickDirectoryPath(prompt: String(localized: "Create Repository")) else { return }
        let url = URL(fileURLWithPath: path)
        do {
            let created = try await GitCLI.initRepository(at: url)
            try await openRepository(at: url)
            if created {
                ui.activeToast = ToastMessage(message: String(localized: "Created \(url.lastPathComponent)"), kind: .ok)
            }
        } catch {
            ui.presentedError = PresentedError(error: error, title: String(localized: "Couldn't create the repository"))
        }
    }

    /// Open Repository menu / sidebar entry. Picks a folder, opens it as a
    /// repo, and surfaces any failure.
    func presentOpenRepositoryPanel() async {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Open Repository")
        panel.prompt = String(localized: "Open")
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
