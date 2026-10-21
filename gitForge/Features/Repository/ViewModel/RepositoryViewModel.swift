import Foundation
import Observation
import os

@Observable
@MainActor
final class RepositoryViewModel {
    static let logger = Logger(subsystem: "com.warwarelabs.gitForge", category: "repo-vm")

    let repository: Repository
    let cli: GitCLI

    /// Log, graph, commit detail and the selected commit's file diff.
    let history: HistoryStore
    /// Status, batch selection, the open file's diff and the commit composer.
    let workingCopy: WorkingCopyStore

    // MARK: Refs / branches / stashes
    var refs: [GitRef] = [] {
        didSet {
            // Watcher reassigns refs on every fs tick — skip the rebuild when
            // nothing changed to avoid chip re-paint storms during scroll.
            guard refs != oldValue else { return }
            refsBySha = Dictionary(grouping: refs) { $0.targetSha }
            // Sorted once per refs change: the Branches view reads these
            // several times per render, i.e. on every filter keystroke.
            localBranches = refs.filter(\.isLocalBranch).sorted { $0.name < $1.name }
            remoteBranches = refs.filter(\.isRemoteBranch).sorted { $0.name < $1.name }
            tags = refs.filter(\.isTag).sorted { $0.name < $1.name }
        }
    }
    private(set) var localBranches: [GitRef] = []
    private(set) var remoteBranches: [GitRef] = []
    private(set) var tags: [GitRef] = []
    /// Cached so chip cells don't regroup `refs` on every scroll tick.
    var refsBySha: [String: [GitRef]] = [:]
    var currentBranchName: String?
    /// Commit HEAD points at, detached or not. Marks HEAD in the graph.
    var headSha: String?
    var stashes: [Stash] = []
    /// Bumped at the start of every `loadRefs()` call. The 4 parallel CLI
    /// reads (refs / current branch / stashes / unmerged) collect into locals
    /// before a single post-await guard — keeps a slow watcher tick from
    /// stomping a fresher refresh's `currentBranchName` after the fresher
    /// one already wrote it.
    var refsGen: UInt64 = 0

    // MARK: Stash detail
    /// The stash detail pane (selection, metadata, files, file diff).
    let stashDetail: StashDetailStore
    /// Local branches whose tip isn't reachable from HEAD. Fed to `git log`
    /// so already-merged branches don't open redundant lanes in the graph.
    var unmergedLocalBranchRefs: [String] = []

    // MARK: Mutations
    /// Set while a mutating local op (commit, stash apply/drop, reset, cherry-pick,
    /// revert, discard, branch/tag delete) is in flight. Backs the disabled
    /// state of UI buttons so a double-click can't enqueue two of the same op
    /// — the cli actor serialises them, but the second one races into the
    /// already-cleared subject/staged state and surfaces a spurious "Nothing
    /// staged" error after a successful first op. Also suspends the watcher
    /// so our own `.git/` writes don't bounce back as external-change events.
    var isMutating: Bool = false {
        didSet {
            guard oldValue != isMutating else { return }
            if isMutating { watcher?.suspend() } else { watcher?.resume() }
        }
    }
    /// Last failed local operation, shown under the commit composer.
    var commitError: String?

    // MARK: Remote
    enum RemoteOperation: Sendable, Equatable { case fetching, pulling, pushing }
    var remoteOperation: RemoteOperation?
    var remoteFailure: RemoteFailure?
    /// A pull refused over local changes, waiting for the user to discard
    /// them; `ShellView` asks and clears it.
    var pullDiscardRequest: PullDiscardRequest?
    /// Last commit / fetch / pull / push that finished cleanly; `ShellView`
    /// shows it as a success toast and clears it. The silent auto-fetch
    /// never sets it.
    var operationSuccess: OperationSuccess?
    var upstream: String?
    var aheadCount: Int = 0
    var behindCount: Int = 0
    var lastFetchedAt: Date?
    /// Bumped at the start of every `loadAheadBehind()` call. Overlapping
    /// invocations (watcher tick + manual fetch both end up walking
    /// `loadRefs → loadAheadBehind`) snapshot it on entry and drop their
    /// `upstream` / `aheadCount` / `behindCount` writes if it moves while
    /// they're awaiting.
    var aheadBehindGen: UInt64 = 0
    /// Set while a silent auto-fetch is in flight. Manual `fetch()` checks
    /// it in addition to `remoteOperation` so the two can't fire duplicate
    /// `git fetch` subprocesses in parallel. Deliberately not bound to the
    /// UI spinner — auto-fetch stays silent by design.
    var autoFetchInFlight: Bool = false

    // MARK: Pull / merge requests
    /// List + detail of the repo's PRs/MRs. Local integration of a PR stays
    /// on the view model (`attemptLocalMergeForPullRequest`).
    let pullRequests: PullRequestStore

    // MARK: Conflicts
    var mergeState: MergeState = .clean
    /// Resolver state: unmerged files, hunks of the selected one, picks.
    let conflicts: ConflictStore
    /// SHA of the stash whose apply/pop left the tree `.unmerged`. Lets
    /// `abortStashApply()` undo exactly the paths that stash touched instead
    /// of resetting the whole tree. Cleared once the tree is clean again.
    var conflictedStashSha: String?

    // MARK: Identity
    /// `user.name` / `user.email` resolved for this repo (local override
    /// wins over global). Refreshed by `refreshIdentity()` on bootstrap and
    /// after external changes; nil before the first read lands.
    private(set) var repoIdentity: RepoIdentity?
    /// Bumped at the start of every identity op (refresh / apply / clear).
    /// `refreshIdentity` snapshots it on entry and drops its write if the
    /// token moved while it was awaiting — keeps a slow watcher-driven read
    /// from stomping a fresher apply/clear.
    var identityGen: UInt64 = 0

    /// Setter helper so `+Identity` (different file) can write through the
    /// `private(set)` wall. Same pattern as `cacheDetail` / `setInFlightDetail`.
    func setRepoIdentity(_ value: RepoIdentity?) {
        repoIdentity = value
    }

    // MARK: Reactivity
    private var watcher: RepositoryWatcher?
    private let autoFetcher = AutoFetcher()
    /// Tasks the session's stores spawn from `didSet` reactions (amend
    /// prefill, commit / working-copy diff loads…). `stopReactivity()`
    /// cancels them all.
    let tasks: OwnedTasks

    /// `credentials`: signs network git commands with the repo's hosting
    /// account (`AppState` passes the account provider).
    init(repository: Repository, credentials: GitCredentialProvider? = nil,
         pullRequestAuth: AccountPullRequestAuth? = nil) {
        self.repository = repository
        let cli = GitCLI(workingDirectory: repository.url, credentials: credentials)
        self.cli = cli
        let repoPath = repository.url.path(percentEncoded: false)
        if let pullRequestAuth {
            self.pullRequests = PullRequestStore(cli: cli,
                                                 auth: { host, rejected in
                                                     await pullRequestAuth.access(host: host, repoPath: repoPath, rejected: rejected)
                                                 },
                                                 silentAuth: { host, rejected in
                                                     await pullRequestAuth.access(host: host, repoPath: repoPath,
                                                                                  rejected: rejected, interactive: false)
                                                 },
                                                 resolveHost: { await pullRequestAuth.remoteHost(cli) },
                                                 suggestInstance: { await pullRequestAuth.suggestedInstance(cli) })
        } else {
            self.pullRequests = PullRequestStore(cli: cli)
        }
        self.stashDetail = StashDetailStore(cli: cli)
        self.conflicts = ConflictStore(repositoryURL: repository.url)
        let tasks = OwnedTasks()
        self.tasks = tasks
        self.history = HistoryStore(cli: cli, tasks: tasks)
        self.workingCopy = WorkingCopyStore(cli: cli, repositoryURL: repository.url, tasks: tasks)
        history.refsSource = self
    }

    /// Idempotent. Call after `loadInitial` so the first reads aren't
    /// racing with watcher-driven refreshes.
    func startReactivity(autoFetchIntervalSeconds: Int) {
        if watcher == nil {
            watcher = RepositoryWatcher(repository: repository.url) { [weak self] in
                await self?.refreshFromExternalChange()
            }
        }
        autoFetcher.start(intervalSeconds: autoFetchIntervalSeconds) { [weak self] in
            await self?.fetchSilently() ?? false
        }
    }

    func stopReactivity() {
        watcher = nil
        autoFetcher.stop()
        // Cancel any internal tasks we own — without this, a half-finished
        // `prefillFromHead` or `loadCommitFileDiff` would keep the stores
        // alive (and their commits/graphLayouts/detailCache in memory) for
        // as long as it takes the underlying git subprocess to drain.
        tasks.cancelAll()
        purgeCaches()
    }

    /// Drops the heavy in-memory caches associated with the open repo. Views
    /// retaining the VM via SwiftUI no longer pin gigabytes worth of commit
    /// graphs / diffs / file lists once the user moves to another repo. The
    /// next `loadInitial` reseeds everything.
    private func purgeCaches() {
        history.purge()
        workingCopy.purge()
        refs = []
        refsBySha = [:]
        stashes = []
        unmergedLocalBranchRefs = []
        stashDetail.close()
        conflicts.clear()
        pullRequests.reset()
        repoIdentity = nil
        upstream = nil
        aheadCount = 0
        behindCount = 0
    }

    /// Trigger a watcher refresh — used when the app returns to foreground.
    /// `force` skips the watcher cooldown so user-visible signals (becoming
    /// active, window key) always produce a refresh.
    func pokeReactivity(force: Bool = false) {
        watcher?.poke(force: force)
    }

    /// Pause periodic background work when the app loses focus. Keeps the
    /// FS watcher armed (it's cheap and the OS suppresses events while we
    /// sleep anyway), but stops the auto-fetcher loop so we don't burn
    /// battery talking to remotes the user can't see.
    func pauseBackgroundWork() {
        autoFetcher.pause()
    }

    /// Resume what `pauseBackgroundWork` paused.
    func resumeBackgroundWork() {
        autoFetcher.resume()
    }

    /// Watcher-driven refresh. Skips the log reload unless HEAD or a local
    /// branch tip actually moved — letting the watcher reload it on every
    /// tick was the source of feedback loops with our own write paths. Every
    /// local tip counts, not just HEAD's: the graph walks all local branches,
    /// so a commit made in another worktree or a `git branch -f` from the
    /// terminal must show up too.
    private func refreshFromExternalChange() async {
        let previousBranch = currentBranchName
        let previousTips = localBranchTips
        async let statusTask: Void = workingCopy.refreshStatus()
        async let refsTask: Void = loadRefs()
        async let conflictTask: Void = loadConflictState()
        async let identityTask: Void = refreshIdentity()
        _ = await statusTask
        _ = await refsTask
        _ = await conflictTask
        _ = await identityTask
        // Reload the diff of whatever the user is currently looking at, so an
        // external edit / discard repaints the right pane immediately. Without
        // this the file row updates but the diff stays on the previous
        // snapshot until the user re-selects.
        await workingCopy.reloadSelectedDiff()
        if currentBranchName != previousBranch || localBranchTips != previousTips {
            await history.reloadLog()
        }
    }

    /// Local branch name → tip SHA.
    private var localBranchTips: [String: String] {
        Dictionary(refs.filter(\.isLocalBranch).map { ($0.name, $0.targetSha) },
                   uniquingKeysWith: { first, _ in first })
    }

    /// Background fetch driven by `AutoFetcher` — failures are logged, not
    /// toasted. Mutually exclusive with manual `fetch()` via
    /// `autoFetchInFlight`; the manual op is also gated on `remoteOperation`
    /// so the two paths can't fire duplicate `git fetch` subprocesses.
    /// Returns whether the auto-fetch reached the remote successfully. The
    /// AutoFetcher uses the bool to drive its offline backoff — repeated
    /// network failures should stop hammering the network every 30s.
    private func fetchSilently() async -> Bool {
        guard remoteOperation == nil, !autoFetchInFlight else { return false }
        autoFetchInFlight = true
        defer { autoFetchInFlight = false }
        do {
            try await GitNetworkContext.$isBackground.withValue(true) {
                try await cli.fetchAll()
            }
            lastFetchedAt = .now
            // `loadRefs()` already calls `loadAheadBehind()` at its tail,
            // so a separate call here would just duplicate the rev-list.
            await loadRefs()
            return true
        } catch {
            Self.logger.debug("auto-fetch failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

extension RepositoryViewModel: HistoryRefsSource {}
