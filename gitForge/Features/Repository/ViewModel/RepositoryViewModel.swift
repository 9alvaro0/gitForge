import Foundation
import Observation
import os

@Observable
@MainActor
final class RepositoryViewModel {
    /// Cap on `git log` pagination during `revealCommit(...)` — prevents a
    /// stray ref from quietly walking the entire history. The page size
    /// itself lives in `AppTheme.persistedCommitPageSize()` so the user
    /// can tune it from Settings.
    static let maxRevealPages = 10

    static let logger = Logger(subsystem: "com.warwarelabs.gitForge", category: "repo-vm")

    let repository: Repository
    let cli: GitCLI

    // MARK: Log
    var commits: [Commit] = []
    var isLoadingInitial = false
    var isLoadingMore = false
    var hasMore = true
    var loadError: String?
    /// Cumulative number of commits `git log` has produced for the current
    /// scope, **before** client-side filters like `dropStashInternals` shrink
    /// the array. Used as `--skip` for pagination so a filtered page never
    /// causes the next walk to overlap with already-loaded commits (which
    /// would surface as duplicate IDs in the History `ForEach`).
    var loadedRawCount: Int = 0
    /// `false` until a `loadInitial()` for the current scope completes.
    /// `resetLog()` clears it so the skeleton can show again on a fresh
    /// branch/checkout. Drives the History skeleton without the
    /// "in-flight loadInitial" race that flickered `isLoadingInitial` and
    /// could trap the placeholder when two checkouts overlapped.
    var hasLoadedLogForCurrentScope = false

    var selectedCommitId: Commit.ID? {
        didSet {
            guard oldValue != selectedCommitId else { return }
            selectedCommitFile = nil
            commitFileDiff = []
            guard
                let id = selectedCommitId,
                let commit = commits.first(where: { $0.id == id })
            else { return }
            Task { await selectFirstFile(for: commit) }
        }
    }

    // MARK: Detail
    var detailCache: [String: CommitDetail] = [:]
    var loadingDetailFor: String?

    /// Auto-selects the first changed file once the detail is available so the
    /// diff pane reflects the freshly clicked commit instead of keeping the
    /// previous selection.
    private func selectFirstFile(for commit: Commit) async {
        let loaded = await detail(for: commit)
        guard
            selectedCommitId == commit.id,
            selectedCommitFile == nil,
            let path = loaded?.files.first?.path
        else { return }
        selectedCommitFile = path
    }

    // MARK: Refs / branches / stashes
    var refs: [GitRef] = [] {
        didSet { refsBySha = Dictionary(grouping: refs) { $0.targetSha } }
    }
    /// Pre-grouped index of refs by their target SHA. Recomputed only when
    /// `refs` is reassigned (in `loadRefs`), instead of every time a row's
    /// chip cell asks for it during scroll. The graph row count is bounded by
    /// the number of refs in the repo, not by the visible commits.
    var refsBySha: [String: [GitRef]] = [:]
    var currentBranchName: String?
    var stashes: [Stash] = []

    // Stash detail (drives StashDetailView)
    var selectedStash: Stash?
    var stashDetail: StashDetail?
    var stashDetailLoading: Bool = false
    var stashDetailError: String?
    var selectedStashFile: String?
    var stashFileDiff: [DiffHunk] = []
    var loadingStashFileDiff: Bool = false
    var stashFileDiffEmptyState: DiffEmptyState = .empty
    /// Full ref-names of local branches whose tip is NOT reachable from HEAD.
    /// Feeds the graph log scope so we don't open a separate lane for every
    /// already-merged branch ref still lingering locally. Refreshed by
    /// `loadRefs`. Empty by default (no filter applied) until first refresh.
    var unmergedLocalBranchRefs: [String] = []

    // MARK: Graph
    var graphLayouts: [GraphRowLayout] = []
    var graphMaxLanes: Int = 1

    // MARK: Working copy
    var status: WorkingCopyStatus = WorkingCopyStatus(files: [])
    var isLoadingStatus = false
    /// `false` until the first `refreshStatus()` completes for this VM.
    /// Lets the UI distinguish "never loaded" from "loaded and clean", so
    /// the Changes view doesn't briefly flash "Working tree is clean"
    /// during the initial load chain (loadInitial → loadRefs → refreshStatus).
    var hasLoadedStatusOnce = false
    var commitSubject: String = ""
    var commitBody: String = ""
    var amendMode: Bool = false {
        didSet {
            guard oldValue != amendMode, amendMode else {
                if !amendMode {
                    commitSubject = ""
                    commitBody = ""
                }
                return
            }
            Task { await prefillFromHead() }
        }
    }
    var commitError: String?

    // MARK: Diffs
    var selectedCommitFile: String? {
        didSet {
            guard oldValue != selectedCommitFile else { return }
            if let path = selectedCommitFile, let commit = selectedCommit {
                Task { await loadCommitFileDiff(sha: commit.sha, path: path) }
            }
        }
    }
    var commitFileDiff: [DiffHunk] = []
    /// Why the current `commitFileDiff` is empty (binary, rename-only, etc.).
    /// Lets the diff pane print a meaningful placeholder instead of the
    /// catch-all "No changes" copy.
    var commitFileDiffEmptyState: DiffEmptyState = .empty
    var loadingCommitFileDiff = false

    var selectedWorkingCopyFile: WorkingCopyFile? {
        didSet {
            guard oldValue != selectedWorkingCopyFile else { return }
            if let file = selectedWorkingCopyFile {
                Task { await loadWorkingCopyDiff(file: file) }
            } else {
                workingCopyDiff = []
            }
        }
    }
    var workingCopyDiff: [DiffHunk] = []
    /// Why the current `workingCopyDiff` is empty. Same role as
    /// `commitFileDiffEmptyState` but for the Changes view.
    var workingCopyDiffEmptyState: DiffEmptyState = .empty
    var loadingWorkingCopyDiff = false

    // MARK: Navigation
    var scrollTargetSha: String?
    var isRevealingCommit = false

    // MARK: Remote
    enum RemoteOperation: Sendable, Equatable { case fetching, pulling, pushing }
    var remoteOperation: RemoteOperation?
    var remoteFailure: RemoteFailure?
    var upstream: String?
    var aheadCount: Int = 0
    var behindCount: Int = 0
    var lastFetchedAt: Date?

    // MARK: Pull / merge requests
    var pullRequests: [PullRequest] = []
    var pullRequestsHost: RemoteHost?
    var pullRequestsLoading: Bool = false
    var pullRequestsError: String?
    /// Set when the host is detected but no token is configured. Drives the
    /// "Connect a host" empty state in `PullsView`.
    var pullRequestsRequiresToken: Bool = false
    var pullRequestsLastLoadedAt: Date?

    // Detail (drives PullRequestDetailView)
    var selectedPullRequest: PullRequest?
    var pullRequestDetail: PullRequestDetail?
    var pullRequestCommits: [PullRequestCommit] = []
    var pullRequestFiles: [PullRequestFileChange] = []
    var pullRequestDetailLoading: Bool = false
    var pullRequestDetailError: String?
    /// True while a "try local merge" attempt is running for the open PR.
    /// Drives the spinner / disabled state on the resolve-locally button.
    var pullRequestLocalMergeRunning: Bool = false

    // MARK: Conflicts
    var mergeState: MergeState = .clean
    var conflictFiles: [ConflictFile] = []
    var conflictHunks: [ConflictHunk] = []
    var selectedConflictPath: String?
    var conflictPicks: [UUID: ConflictHunk.Pick] = [:]

    // MARK: Reactivity
    private var watcher: RepositoryWatcher?
    private let autoFetcher = AutoFetcher()

    init(repository: Repository) {
        self.repository = repository
        self.cli = GitCLI(workingDirectory: repository.url)
    }

    /// Wire the filesystem watcher and (optional) auto-fetch timer. Called by
    /// the host view once after `loadInitial` so the first reads aren't
    /// fighting with refresh notifications. Idempotent.
    func startReactivity(autoFetchIntervalSeconds: Int) {
        if watcher == nil {
            watcher = RepositoryWatcher(repository: repository.url) { [weak self] in
                await self?.refreshFromExternalChange()
            }
        }
        autoFetcher.start(intervalSeconds: autoFetchIntervalSeconds) { [weak self] in
            await self?.fetchSilently()
        }
    }

    func stopReactivity() {
        watcher = nil
        autoFetcher.stop()
    }

    /// Manually pulse the watcher pipeline (e.g. when the app comes back to
    /// the foreground) so the user immediately sees external changes.
    func pokeReactivity() {
        watcher?.poke()
    }

    /// Refresh path for filesystem-driven changes. `loadRefs` already calls
    /// `loadAheadBehind` internally, and we skip the log reload when nothing
    /// HEAD-changing happened to keep things cheap. The log refresh is
    /// triggered explicitly by remote/branch operations elsewhere — letting
    /// the watcher reload it on every tick was the source of feedback loops.
    private func refreshFromExternalChange() async {
        let previousHeadSha = commits.first?.sha
        await refreshStatus()
        await loadRefs()
        await loadConflictState()
        // Only refresh the log if HEAD actually moved. We detect that via the
        // ref of the current branch — much cheaper than re-running git log.
        if let currentBranch = currentBranchName,
           let headSha = refs.first(where: { $0.isLocalBranch && $0.name == currentBranch })?.targetSha,
           headSha != previousHeadSha {
            await reloadLog()
        }
    }

    /// Silent fetch: never surfaces a toast on success, only logs failures.
    /// Used by the AutoFetcher timer.
    private func fetchSilently() async {
        guard remoteOperation == nil else { return }
        do {
            try await cli.fetchAll()
            lastFetchedAt = .now
            await loadRefs()
            await loadAheadBehind()
        } catch {
            Self.logger.debug("auto-fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Computed views

    var selectedCommit: Commit? {
        guard let id = selectedCommitId else { return nil }
        return commits.first { $0.id == id }
    }

    var localBranches: [GitRef] {
        refs.filter(\.isLocalBranch).sorted { $0.name < $1.name }
    }

    var remoteBranches: [GitRef] {
        refs.filter(\.isRemoteBranch).sorted { $0.name < $1.name }
    }

    var tags: [GitRef] {
        refs.filter(\.isTag).sorted { $0.name < $1.name }
    }
}
