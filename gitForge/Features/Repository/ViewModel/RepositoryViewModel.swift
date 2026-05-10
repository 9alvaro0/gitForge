import Foundation
import Observation
import os

@Observable
@MainActor
final class RepositoryViewModel {
    /// Hard cap on `revealCommit(...)` pagination — without it a stray ref
    /// can quietly walk the entire history.
    static let maxRevealPages = 10

    static let logger = Logger(subsystem: "com.warwarelabs.gitForge", category: "repo-vm")

    let repository: Repository
    let cli: GitCLI

    // MARK: Log
    var commits: [Commit] = [] {
        // `uniquingKeysWith: { _, new in new }` instead of
        // `uniqueKeysWithValues:` — the latter traps on duplicate ids, and a
        // duplicate would only happen if the `--skip` invariant in
        // `loadedRawCount` ever leaks. Don't crash the app on a leak.
        didSet {
            commitsById = Dictionary(commits.map { ($0.id, $0) },
                                     uniquingKeysWith: { _, new in new })
        }
    }
    /// Mirror of `commits` keyed by id, kept in sync by `commits.didSet`.
    private(set) var commitsById: [Commit.ID: Commit] = [:]
    var isLoadingInitial = false
    var isLoadingMore = false
    var hasMore = true
    var loadError: String?
    /// Raw commits produced by `git log` for the current scope, *before*
    /// `dropStashInternals` shrinks `commits`. Used as `--skip` so the next
    /// page can't overlap with what's already loaded.
    var loadedRawCount: Int = 0
    /// Drives the History skeleton. Kept separate from `isLoadingInitial`
    /// because two overlapping checkouts could trap the placeholder when
    /// the boolean alone was the trigger.
    var hasLoadedLogForCurrentScope = false
    /// Bumped at the start of every log op (initial / reload / pagination /
    /// reveal). Each op snapshots it on entry and drops its writes if the
    /// token moved while it was awaiting — keeps a slow `git log` from
    /// stomping a fresher reload.
    var logGen: UInt64 = 0

    var selectedCommitId: Commit.ID? {
        didSet {
            guard oldValue != selectedCommitId else { return }
            // Invalidate in-flight diff loads from the previous commit.
            commitFileDiffGen &+= 1
            selectedCommitFile = nil
            commitFileDiff = []
            commitFileDiffEmptyState = .empty
            loadingCommitFileDiff = false
            guard
                let id = selectedCommitId,
                let commit = commitsById[id]
            else { return }
            Task { await selectFirstFile(for: commit) }
        }
    }

    // MARK: Detail
    private(set) var detailCache: [String: CommitDetail] = [:]
    /// Insertion order of `detailCache` keys; trimmed FIFO when the cap is
    /// exceeded so a long browsing session can't grow the cache forever.
    private var detailCacheOrder: [String] = []
    private static let detailCacheCap = 200
    /// Tasks currently fetching a `CommitDetail`, keyed by sha. Lets multiple
    /// concurrent callers (e.g. row click + `selectFirstFile`) coalesce onto
    /// a single CLI invocation instead of duplicating work.
    private var inFlightDetails: [String: Task<CommitDetail?, Never>] = [:]
    private(set) var loadingDetailFor: String?

    func cacheDetail(_ detail: CommitDetail, for sha: String) {
        if detailCache[sha] == nil {
            detailCacheOrder.append(sha)
        }
        detailCache[sha] = detail
        while detailCacheOrder.count > Self.detailCacheCap {
            let oldest = detailCacheOrder.removeFirst()
            detailCache.removeValue(forKey: oldest)
        }
    }

    func setInFlightDetail(_ task: Task<CommitDetail?, Never>?, for sha: String) {
        if let task {
            inFlightDetails[sha] = task
        } else {
            inFlightDetails.removeValue(forKey: sha)
        }
    }

    func inFlightDetail(for sha: String) -> Task<CommitDetail?, Never>? {
        inFlightDetails[sha]
    }

    func setLoadingDetail(_ sha: String?) {
        loadingDetailFor = sha
    }

    /// Re-checks `selectedCommitId` after the await so a slow detail load
    /// can't auto-select a file in a commit the user already left.
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
        didSet {
            // Watcher reassigns refs on every fs tick — skip the rebuild when
            // nothing changed to avoid chip re-paint storms during scroll.
            guard refs != oldValue else { return }
            refsBySha = Dictionary(grouping: refs) { $0.targetSha }
        }
    }
    /// Cached so chip cells don't regroup `refs` on every scroll tick.
    var refsBySha: [String: [GitRef]] = [:]
    var currentBranchName: String?
    var stashes: [Stash] = []

    // MARK: Stash detail
    var selectedStash: Stash?
    var stashDetail: StashDetail?
    var stashDetailLoading: Bool = false
    var stashDetailError: String?
    var selectedStashFile: String?
    var stashFileDiff: [DiffHunk] = []
    var loadingStashFileDiff: Bool = false
    var stashFileDiffEmptyState: DiffEmptyState = .empty
    /// Local branches whose tip isn't reachable from HEAD. Fed to `git log`
    /// so already-merged branches don't open redundant lanes in the graph.
    var unmergedLocalBranchRefs: [String] = []

    // MARK: Graph
    var graphLayouts: [GraphRowLayout] = []
    var graphMaxLanes: Int = 1

    // MARK: Working copy
    var status: WorkingCopyStatus = WorkingCopyStatus(files: [])
    var isLoadingStatus = false
    /// Distinguishes "never loaded" from "loaded and clean" so the Changes
    /// view doesn't briefly flash "Working tree is clean" on first paint.
    var hasLoadedStatusOnce = false
    var commitSubject: String = ""
    var commitBody: String = ""
    var amendMode: Bool = false {
        didSet {
            guard oldValue != amendMode else { return }
            if amendMode {
                Task { await prefillFromHead() }
            } else {
                commitSubject = ""
                commitBody = ""
            }
        }
    }
    var commitError: String?

    // MARK: Diffs
    var selectedCommitFile: String? {
        didSet {
            guard oldValue != selectedCommitFile else { return }
            // Bump even on nil so an in-flight load can't write back over
            // the now-empty pane.
            commitFileDiffGen &+= 1
            if let path = selectedCommitFile, let commit = selectedCommit {
                Task { await loadCommitFileDiff(sha: commit.sha, path: path) }
            }
        }
    }
    var commitFileDiff: [DiffHunk] = []
    /// Why the diff is empty (binary, rename-only, …) so the pane can show
    /// something better than a catch-all "No changes".
    var commitFileDiffEmptyState: DiffEmptyState = .empty
    var loadingCommitFileDiff = false
    /// Selection-change token. Bumped by the didSets that own this pane
    /// (`selectedCommitId`, `selectedCommitFile`); loaders snapshot it on
    /// entry and drop their write-back if it moves while they're awaiting.
    var commitFileDiffGen: UInt64 = 0

    var selectedWorkingCopyFile: WorkingCopyFile? {
        didSet {
            guard oldValue != selectedWorkingCopyFile else { return }
            workingCopyDiffGen &+= 1
            if let file = selectedWorkingCopyFile {
                Task { await loadWorkingCopyDiff(file: file) }
            } else {
                workingCopyDiff = []
                workingCopyDiffEmptyState = .empty
                loadingWorkingCopyDiff = false
            }
        }
    }
    var workingCopyDiff: [DiffHunk] = []
    /// Counterpart to `commitFileDiffEmptyState` for the Changes view.
    var workingCopyDiffEmptyState: DiffEmptyState = .empty
    var loadingWorkingCopyDiff = false
    /// Counterpart to `commitFileDiffGen` for the working-copy diff pane.
    var workingCopyDiffGen: UInt64 = 0

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
    /// Host detected but no token configured — drives the "Connect a host"
    /// empty state in `PullsView`.
    var pullRequestsRequiresToken: Bool = false
    var pullRequestsLastLoadedAt: Date?

    // MARK: PR detail
    var selectedPullRequest: PullRequest?
    var pullRequestDetail: PullRequestDetail?
    var pullRequestCommits: [PullRequestCommit] = []
    var pullRequestFiles: [PullRequestFileChange] = []
    var pullRequestDetailLoading: Bool = false
    var pullRequestDetailError: String?
    /// Drives the spinner on the "Resolve locally" button while a try-merge
    /// attempt is in flight.
    var pullRequestLocalMergeRunning: Bool = false

    // MARK: Conflicts
    var mergeState: MergeState = .clean
    var conflictFiles: [ConflictFile] = []
    var conflictHunks: [ConflictHunk] = []
    var selectedConflictPath: String?
    var conflictPicks: [UUID: ConflictHunk.Pick] = [:]
    /// Counterpart to `commitFileDiffGen` for the conflict hunks pane.
    var conflictHunksGen: UInt64 = 0

    // MARK: Reactivity
    private var watcher: RepositoryWatcher?
    private let autoFetcher = AutoFetcher()

    init(repository: Repository) {
        self.repository = repository
        self.cli = GitCLI(workingDirectory: repository.url)
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
            await self?.fetchSilently()
        }
    }

    func stopReactivity() {
        watcher = nil
        autoFetcher.stop()
    }

    /// Force a watcher refresh — used when the app returns to foreground.
    func pokeReactivity() {
        watcher?.poke()
    }

    /// Watcher-driven refresh. Skips the log reload unless HEAD actually
    /// moved — letting the watcher reload it on every tick was the source
    /// of feedback loops with our own write paths.
    private func refreshFromExternalChange() async {
        // Snapshot what HEAD looked like before refresh. We use both pieces:
        //  · branch name change (covers attaching/detaching HEAD externally,
        //    `git switch` to a different branch, …).
        //  · tip sha change (covers normal commits/pulls on the same branch).
        // A pure detached→detached HEAD move via another tool isn't caught
        // here without an extra `rev-parse HEAD` round-trip; very rare in
        // practice, accept it.
        let previousBranch = currentBranchName
        let previousHeadSha = previousBranch.flatMap { branch in
            refs.first(where: { $0.isLocalBranch && $0.name == branch })?.targetSha
        }
        await refreshStatus()
        await loadRefs()
        await loadConflictState()
        let newHeadSha = currentBranchName.flatMap { branch in
            refs.first(where: { $0.isLocalBranch && $0.name == branch })?.targetSha
        }
        if currentBranchName != previousBranch || newHeadSha != previousHeadSha {
            await reloadLog()
        }
    }

    /// Background fetch driven by `AutoFetcher` — failures are logged, not
    /// toasted.
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
        return commitsById[id]
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
