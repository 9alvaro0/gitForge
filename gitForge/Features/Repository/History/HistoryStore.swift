import Foundation
import Observation

/// The session's refs as the graph sees them. `RepositoryViewModel` owns
/// them (`loadRefs`) and conforms; the history store reads them to build the
/// graph scope and writes back the fresh stashes / unmerged branches it reads
/// alongside each first page, so the scope and the page always match.
@MainActor
protocol HistoryRefsSource: AnyObject {
    var stashes: [Stash] { get set }
    var unmergedLocalBranchRefs: [String] { get set }
    var refsBySha: [String: [GitRef]] { get }
}

/// History: the paged log, its graph layout, the commit detail cache, the
/// selected commit and the diff of its selected file. Owned by
/// `RepositoryViewModel` (`viewModel.history`). Refs and stashes stay on the
/// view model, which also decides when the log reloads (after a commit,
/// checkout, pull, watcher tick…).
@Observable
@MainActor
final class HistoryStore {
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
            tasks.track { [weak self] in await self?.selectFirstFile(for: commit) }
        }
    }

    var selectedCommit: Commit? {
        guard let id = selectedCommitId else { return nil }
        return commitsById[id]
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

    // MARK: Graph
    var graphLayouts: [GraphRowLayout] = []
    var graphMaxLanes: Int = 1
    /// Bumped at the start of every `recomputeGraph()` call. The layout work
    /// runs off-actor (50k commits would otherwise stutter the scroll on
    /// page load); the post-await guard drops stale results when the user
    /// scrolls fast enough to enqueue multiple page loads.
    var graphLayoutGen: UInt64 = 0

    // MARK: Commit file diff
    var selectedCommitFile: String? {
        didSet {
            guard oldValue != selectedCommitFile else { return }
            // Bump even on nil so an in-flight load can't write back over
            // the now-empty pane.
            commitFileDiffGen &+= 1
            if let path = selectedCommitFile, let commit = selectedCommit {
                tasks.track { [weak self] in await self?.loadCommitFileDiff(sha: commit.sha, path: path) }
            } else {
                // No new loader will take over the flag.
                loadingCommitFileDiff = false
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

    // MARK: Dependencies
    private let cli: GitCLI
    private let tasks: OwnedTasks
    @ObservationIgnored weak var refsSource: (any HistoryRefsSource)?

    init(cli: GitCLI, tasks: OwnedTasks) {
        self.cli = cli
        self.tasks = tasks
    }

    /// Drops the heavy caches (log, graph, details, diff) when the session
    /// stops. The next `loadInitial` reseeds everything.
    func purge() {
        commits = []
        commitsById = [:]
        graphLayouts = []
        detailCache.removeAll()
        detailCacheOrder.removeAll()
        inFlightDetails.removeAll()
        commitFileDiff = []
    }

    /// Selects `ref`'s tip. Returns `false`, leaving the selection alone,
    /// when that commit isn't in the loaded log.
    @discardableResult
    func revealInHistory(_ ref: GitRef) -> Bool {
        guard commits.contains(where: { $0.sha == ref.targetSha }) else { return false }
        selectedCommitId = ref.targetSha
        return true
    }

    // MARK: Scope

    private var stashes: [Stash] { refsSource?.stashes ?? [] }

    /// Refs the graph walks. HEAD goes first so its tip anchors the top of
    /// the topo-ordered log (matches GitKraken). Local branches not merged
    /// into HEAD become their own lanes; merged ones ride along via HEAD's
    /// merge ancestry — passing them as separate tips would just bloat the
    /// column count. Tags are labels on already-walked commits; stashes
    /// surface as their own dashed lanes.
    func graphScope() -> [String] {
        var refs: [String] = ["HEAD"]
        refs.append(contentsOf: refsSource?.unmergedLocalBranchRefs ?? [])
        refs.append("--tags")
        refs.append(contentsOf: stashes.map(\.sha))
        return refs
    }

    // MARK: Log loading

    // Gen-token contract for the log:
    //   • `loadInitial` / `reloadLog` replace `commits`, so they bump
    //     `logGen` and any older load or pagination drops its result.
    //   • Pagination (`loadMoreIfNeeded`) only *snapshots*
    //     `logGen`: a reload supersedes a page load, never the reverse —
    //     otherwise scrolling during a watcher refresh discarded the fresh
    //     first page and left the graph stale.
    //   • Each loading flag is cleared by the operation that set it, always.
    //     The ops are non-reentrant (guarded on their own flag), so there's
    //     no newer owner to protect; clearing only "if gen still matches"
    //     left the flag stuck at true after a reload, which blocked
    //     pagination (or `loadInitial`) for the rest of the session.

    func loadInitial() async {
        guard commits.isEmpty, !isLoadingInitial else { return }
        logGen &+= 1
        let gen = logGen
        isLoadingInitial = true
        loadError = nil
        defer {
            isLoadingInitial = false
            if gen == logGen { hasLoadedLogForCurrentScope = true }
        }
        let pageSize = GitPreferences.commitPageSize
        do {
            // Stashes + unmerged-branch refs feed graphScope(); without them
            // the first paint walks an incomplete scope. Run both in
            // parallel when neither has been seeded by an earlier loadRefs().
            let needsStashes = stashes.isEmpty
            let needsUnmerged = refsSource?.unmergedLocalBranchRefs.isEmpty ?? true
            if needsStashes || needsUnmerged {
                async let stashTask = cli.stashes()
                async let unmergedTask = cli.unmergedLocalBranches()
                if needsStashes {
                    let fresh = (try? await stashTask) ?? []
                    refsSource?.stashes = fresh
                }
                if needsUnmerged {
                    let fresh = (try? await unmergedTask) ?? []
                    refsSource?.unmergedLocalBranchRefs = fresh
                }
                guard gen == logGen else { return }
            }
            let page = try await cli.log(limit: pageSize, skip: 0, refs: graphScope())
            guard gen == logGen else { return }
            commits = page
            loadedRawCount = page.count
            dropStashInternals()
            hasMore = page.count == pageSize
            selectedCommitId = commits.first?.id
            await recomputeGraph()
        } catch {
            guard gen == logGen else { return }
            loadError = error.userMessage
        }
    }

    /// Refetches the first page using the current graph scope and swaps it
    /// into `commits` atomically — no flash of empty during the fetch, and
    /// the ScrollView keeps its offset when HEAD moves (checkout, pull,
    /// commit, merge, watcher tick…).
    ///
    /// Preserves the user's selection when the previously-selected commit
    /// is still in the new page; otherwise falls back to the new first
    /// commit (matching `loadInitial`'s default).
    func reloadLog() async {
        let previousSelection = selectedCommitId
        logGen &+= 1
        let gen = logGen
        loadError = nil
        let pageSize = GitPreferences.commitPageSize
        do {
            async let stashTask = cli.stashes()
            async let unmergedTask = cli.unmergedLocalBranches()
            let freshStashes = (try? await stashTask) ?? []
            let freshUnmerged = (try? await unmergedTask) ?? []
            guard gen == logGen else { return }
            refsSource?.stashes = freshStashes
            refsSource?.unmergedLocalBranchRefs = freshUnmerged
            let page = try await cli.log(limit: pageSize, skip: 0, refs: graphScope())
            guard gen == logGen else { return }
            commits = page
            loadedRawCount = page.count
            dropStashInternals()
            hasMore = page.count == pageSize
            if let prev = previousSelection, commitsById[prev] == nil {
                selectedCommitId = commits.first?.id
            }
            await recomputeGraph()
            hasLoadedLogForCurrentScope = true
        } catch {
            guard gen == logGen else { return }
            loadError = error.userMessage
        }
    }

    func loadMoreIfNeeded(currentItem: Commit) async {
        guard hasMore, !isLoadingMore else { return }
        guard let last = commits.last, last.id == currentItem.id else { return }
        let gen = logGen
        isLoadingMore = true
        loadError = nil
        defer { isLoadingMore = false }
        let pageSize = GitPreferences.commitPageSize
        do {
            _ = try await paginateNextPage(gen: gen, pageSize: pageSize)
        } catch {
            guard gen == logGen else { return }
            loadError = error.userMessage
        }
    }

    /// Fetches the next page from `loadedRawCount` and merges it. Returns
    /// the freshly fetched commits, or nil when the gen token moved during
    /// the await (a fresher reload kicked in; caller should bail).
    private func paginateNextPage(gen: UInt64, pageSize: Int) async throws -> [Commit]? {
        let next = try await cli.log(limit: pageSize, skip: loadedRawCount, refs: graphScope())
        guard gen == logGen else { return nil }
        loadedRawCount += next.count
        commits.append(contentsOf: next)
        dropStashInternals()
        hasMore = next.count == pageSize
        await recomputeGraph()
        return next
    }

    // MARK: Graph

    /// Moves the (O(n)) layout computation off the main actor so a paginate
    /// or reload over 50k commits doesn't stutter the scroll view. The result
    /// is gated by `graphLayoutGen` so an older detached compute can't
    /// stomp a fresher one when the user scrolls fast enough to enqueue
    /// multiple page loads in flight.
    func recomputeGraph() async {
        graphLayoutGen &+= 1
        let gen = graphLayoutGen
        let stashShas = Set(stashes.map(\.sha))
        let commitsSnapshot = commits
        let refsSnapshot = refsSource?.refsBySha ?? [:]
        let result = await Task.detached { @Sendable in
            GraphLayoutEngine.layouts(for: commitsSnapshot, refsBySha: refsSnapshot, stashShas: stashShas)
        }.value
        guard gen == graphLayoutGen else { return }
        graphLayouts = result.rows
        graphMaxLanes = max(1, result.maxLanes)
    }

    /// Synchronous variant used by SwiftUI previews and any caller that
    /// genuinely needs the graph populated before the next instruction.
    /// Production paths should prefer `recomputeGraph()` to keep the main
    /// actor free.
    func recomputeGraphSync() {
        graphLayoutGen &+= 1
        let stashShas = Set(stashes.map(\.sha))
        let result = GraphLayoutEngine.layouts(for: commits, refsBySha: refsSource?.refsBySha ?? [:],
                                               stashShas: stashShas)
        graphLayouts = result.rows
        graphMaxLanes = max(1, result.maxLanes)
    }

    /// Removes stash *internal* commits — `parent[1]` (index tree) and
    /// `parent[2]` (untracked tree) of each stash. Those are git plumbing
    /// the user never asked for; surfacing them as separate rows clutters
    /// the log. The stash commit itself stays as the dashed dot.
    func dropStashInternals() {
        let stashShas = Set(stashes.map(\.sha))
        guard !stashShas.isEmpty else { return }
        var internals: Set<String> = []
        for commit in commits where stashShas.contains(commit.sha) {
            // parent[0] is the real HEAD when the stash was taken — keep it.
            for (idx, parent) in commit.parentShas.enumerated() where idx >= 1 {
                internals.insert(parent)
            }
        }
        guard !internals.isEmpty else { return }
        commits.removeAll { internals.contains($0.sha) }
    }

    // MARK: Detail

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

    /// Returns the cached `CommitDetail` for `commit`, fetching once if not
    /// cached. Concurrent callers requesting the same sha share a single
    /// in-flight fetch instead of each spawning their own CLI call.
    func detail(for commit: Commit) async -> CommitDetail? {
        if let cached = detailCache[commit.sha] { return cached }
        if let inflight = inFlightDetails[commit.sha] {
            return await inflight.value
        }

        let task = Task<CommitDetail?, Never> { [self] in
            // Innermost defer runs first: clear the loading marker before the
            // in-flight slot, so the UI's "loading" state goes away in sync
            // with the await returning to the original caller.
            defer { inFlightDetails.removeValue(forKey: commit.sha) }
            loadingDetailFor = commit.sha
            defer {
                if loadingDetailFor == commit.sha { loadingDetailFor = nil }
            }
            do {
                let detail = try await cli.commitDetail(for: commit)
                cacheDetail(detail, for: commit.sha)
                return detail
            } catch {
                return nil
            }
        }
        inFlightDetails[commit.sha] = task
        return await task.value
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

    /// Re-reads the open file's diff, e.g. after the whitespace option flips.
    func reloadCommitFileDiff() async {
        guard let path = selectedCommitFile, let commit = selectedCommit else { return }
        commitFileDiffGen &+= 1
        await loadCommitFileDiff(sha: commit.sha, path: path)
    }

    func loadCommitFileDiff(sha: String, path: String) async {
        // Snapshot the selection token. If the user moves on while we await
        // on the CLI, the token will fall behind and we drop the write-back
        // so the pane keeps showing the diff for the *current* selection,
        // not whichever async call finishes last.
        let gen = commitFileDiffGen
        loadingCommitFileDiff = true
        defer {
            if gen == commitFileDiffGen { loadingCommitFileDiff = false }
        }
        do {
            let raw = try await cli.diff(sha: sha, file: path)
            guard gen == commitFileDiffGen else { return }
            let hunks = DiffParser.parse(raw)
            commitFileDiff = hunks
            commitFileDiffEmptyState = hunks.isEmpty ? DiffEmptyState.classifying(raw: raw, ignoringWhitespace: GitPreferences.diffIgnoreWhitespace) : .empty
        } catch {
            guard gen == commitFileDiffGen else { return }
            commitFileDiff = []
            commitFileDiffEmptyState = .empty
        }
    }
}
