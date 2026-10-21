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
    /// Every ref, as `GitCLI.refs()` returns them: the graph names its lines from these.
    var refs: [GitRef] { get }
    /// Commit HEAD points at, detached or not.
    var headSha: String? { get }
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
    /// The published log. The loaders publish it together with its graph
    /// (`publish(_:)`); only tests and previews set it directly.
    var commits: [Commit] = [] {
        // `uniquingKeysWith: { _, new in new }` instead of
        // `uniqueKeysWithValues:` — the latter traps on duplicate ids. The
        // loaders can't produce one (`HistoryLog.appending` skips commits a
        // log that grew between pages repeats), but tests and previews set
        // `commits` directly. Don't crash the app on a duplicate.
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
    /// stash internals were dropped from `commits` (`HistoryLog.rawCount`).
    /// Used as `--skip` so the next page can't overlap with what's already
    /// loaded.
    var loadedRawCount: Int = 0
    /// Stash commits of the published log (`HistoryLog.stashShas`): what the
    /// graph draws as stashes until the log is replaced, whatever the live
    /// stash list says meanwhile.
    private(set) var loadedStashShas: Set<String> = []
    /// Bumped each time a log is published or purged. An append staged on an
    /// older log is dropped instead of landing on rows it wasn't fetched for.
    private(set) var logRevision: UInt64 = 0
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
    /// One row per commit, in the order of `commits`.
    ///
    /// Invariant: once a log has been published, `graphLayouts.count ==
    /// commits.count` after every operation the UI can observe. The loaders
    /// assign the log and its graph in the same main-actor turn, and a
    /// recompute only lands on the log it was computed for.
    var graphLayouts: [GraphRow] = []
    /// Columns the graph uses (`GraphLayout.columnCount`), at least 1.
    var graphMaxLanes: Int = 1
    /// Row index one past the end of each loaded page, as `GraphInput.pageEnds`
    /// wants it: only the first page reserves columns, so loading the next
    /// page leaves every row already drawn as it was (§3.9).
    private(set) var graphPageEnds: [Int] = []
    /// Pool colours for the current accent. Starts at the violet pool;
    /// `HistoryView` sets the real one from the theme.
    private(set) var graphPaletteSize: Int = LaneColors.pool(accent: .violet).count
    /// Bumped by every layout pass a recompute starts and by every log
    /// publish. A recompute's result lands only while its token is current,
    /// so it can't overwrite a newer pass or a log it wasn't computed for.
    var graphLayoutGen: UInt64 = 0
    /// Bumped by `recomputeGraph()`: something the graph reads besides the
    /// log (refs, HEAD, palette) may have changed. A log staged before the
    /// bump recomputes once more after it is published.
    private var graphInputRevision: UInt64 = 0
    /// Lays a graph out, always off the main actor. Tests swap it to hold a
    /// pass and interleave it with another.
    @ObservationIgnored var graphEngine: @Sendable (GraphInput) async -> GraphLayout = {
        CommitGraphEngine.layout($0)
    }

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
        // Drop every load, page and layout still in flight for the old log.
        logGen &+= 1
        logRevision &+= 1
        graphLayoutGen &+= 1
        commits = []
        commitsById = [:]
        loadedRawCount = 0
        loadedStashShas = []
        graphLayouts = []
        graphMaxLanes = 1
        graphPageEnds = []
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
        fetchScope().refs
    }

    /// `graphScope()` and the stashes in it, read together: the stash set a
    /// page is fetched with is the one its log keeps (`HistoryLog.stashShas`),
    /// even if the live list changes while `git log` runs.
    private func fetchScope() -> (refs: [String], stashShas: Set<String>) {
        let stashShas = stashes.map(\.sha)
        var refs: [String] = ["HEAD"]
        refs.append(contentsOf: refsSource?.unmergedLocalBranchRefs ?? [])
        refs.append("--tags")
        refs.append(contentsOf: stashShas)
        return (refs, Set(stashShas))
    }

    // MARK: Log loading

    // Gen-token contract for the log and its graph:
    //   • `loadInitial` / `reloadLog` replace `commits`, so they bump
    //     `logGen` and any older load or pagination drops its result.
    //   • Pagination (`loadMoreIfNeeded`) only *snapshots*
    //     `logGen`: a reload supersedes a page load, never the reverse —
    //     otherwise scrolling during a watcher refresh discarded the fresh
    //     first page and left the graph stale.
    //   • A loaded page is staged (`stageFirstPage` / `stageNextPage`), laid
    //     out off the main actor, and published with its graph in one turn
    //     (`publish`), so a row never draws another log's graph. Publishing
    //     bumps `logRevision` and `graphLayoutGen`.
    //   • A page append also snapshots `logRevision` before it fetches, and
    //     publishes only if no log was published since: a reload that
    //     published while the page was in flight has a different
    //     `loadedRawCount`, so the page would not fit on it. The user's next
    //     scroll to the bottom fetches it again.
    //   • `recomputeGraph()` (refs, HEAD or palette changed) lays out the
    //     published log and lands only while `graphLayoutGen` is unchanged:
    //     a newer recompute or a log published meanwhile drops it. It also
    //     bumps `graphInputRevision`; a log whose layout pass ends after that
    //     bump is laid out again from the current inputs before it is
    //     installed, so a stale layout is never shown. Neither loses the
    //     other: a recompute that starts during a page load either is already
    //     in the page's input or makes the page lay itself out again.
    //   • What goes with a published log (`hasMore`, the selection,
    //     `hasLoadedLogForCurrentScope`) is written in `publish`'s `then`, in
    //     the same main-actor turn as the install. A load that was
    //     superseded writes nothing, so it can't overwrite a newer one.
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
            let scope = fetchScope()
            let page = try await cli.log(limit: pageSize, skip: 0, refs: scope.refs)
            guard gen == logGen else { return }
            await publish(stageFirstPage(page, stashShas: scope.stashShas, logGen: gen)) {
                hasMore = page.count == pageSize
                selectedCommitId = commits.first?.id
            }
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
            let scope = fetchScope()
            let page = try await cli.log(limit: pageSize, skip: 0, refs: scope.refs)
            guard gen == logGen else { return }
            await publish(stageFirstPage(page, stashShas: scope.stashShas, logGen: gen)) {
                hasMore = page.count == pageSize
                if let prev = previousSelection, commitsById[prev] == nil {
                    selectedCommitId = commits.first?.id
                }
                hasLoadedLogForCurrentScope = true
            }
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

    /// Fetches the next page from `loadedRawCount` and publishes it with its
    /// graph. Returns the freshly fetched commits, or nil when the log moved
    /// during the awaits (a fresher reload kicked in; caller should bail).
    private func paginateNextPage(gen: UInt64, pageSize: Int) async throws -> [Commit]? {
        let base = logRevision
        let scope = fetchScope()
        let next = try await cli.log(limit: pageSize, skip: loadedRawCount, refs: scope.refs)
        guard gen == logGen, base == logRevision else { return nil }
        let staged = stageNextPage(next, scopeStashShas: scope.stashShas, logGen: gen, baseRevision: base)
        guard await publish(staged, then: { hasMore = next.count == pageSize }) else { return nil }
        return next
    }

    // MARK: Graph

    /// A log ready to publish, with the graph input snapshotted when it was
    /// staged and the tokens that say whether it is still wanted.
    struct StagedLog {
        let log: HistoryLog
        let input: GraphInput
        /// `logGen` of the operation that fetched it: a newer reload drops it.
        let logGen: UInt64
        /// `logRevision` an appended page was built on; nil for a log that
        /// starts over.
        let baseRevision: UInt64?
        /// `graphInputRevision` when `input` was snapshotted: if it has moved
        /// by the time the pass ends, `publish` lays the log out again.
        let inputRevision: UInt64
    }

    /// The published log, as `HistoryLog`.
    var loadedLog: HistoryLog {
        HistoryLog(commits: commits, rawCount: loadedRawCount, pageEnds: graphPageEnds, stashShas: loadedStashShas)
    }

    /// A log that starts over with `page`. Defaults are for tests: the live
    /// stashes and the current `logGen`; the loaders pass the scope the page
    /// was fetched with and their own token.
    func stageFirstPage(_ page: [Commit], stashShas: Set<String>? = nil, logGen gen: UInt64? = nil) -> StagedLog {
        stage(HistoryLog.firstPage(page, stashShas: stashShas ?? Set(stashes.map(\.sha))),
              logGen: gen ?? logGen, baseRevision: nil)
    }

    /// The published log with `page` appended (`HistoryLog.appending`).
    /// Defaults are for tests, as in `stageFirstPage`; the loader passes the
    /// revision it fetched against.
    func stageNextPage(_ page: [Commit], scopeStashShas: Set<String>? = nil, logGen gen: UInt64? = nil,
                       baseRevision: UInt64? = nil) -> StagedLog {
        let log = loadedLog.appending(page, scopeStashShas: scopeStashShas ?? Set(stashes.map(\.sha)))
        return stage(log, logGen: gen ?? logGen, baseRevision: baseRevision ?? logRevision)
    }

    private func stage(_ log: HistoryLog, logGen gen: UInt64, baseRevision: UInt64?) -> StagedLog {
        StagedLog(log: log, input: graphInput(for: log), logGen: gen, baseRevision: baseRevision,
                  inputRevision: graphInputRevision)
    }

    /// Lays `staged` out off the main actor, then publishes the log and its
    /// graph in one main-actor turn: `commits`, `loadedRawCount`,
    /// `graphPageEnds`, `loadedStashShas`, `graphLayouts` and
    /// `graphMaxLanes`, followed by `finish`, the caller's own state that
    /// goes with this log (`hasMore`, the selection…). Nothing is awaited
    /// between the install and `finish`, so a newer load can't publish in
    /// between and be overwritten.
    ///
    /// If refs, HEAD or the palette changed during a pass (a recompute was
    /// asked for), the log is laid out again from the current ones before
    /// anything is shown, as many times as it takes. Returns false, running
    /// nothing, when a newer reload superseded it or (for a page) another log
    /// was published since its base.
    @discardableResult
    func publish(_ staged: StagedLog, then finish: @MainActor () -> Void = {}) async -> Bool {
        var revision = staged.inputRevision
        var layout = await layOut(staged.input)
        while isWanted(staged) {
            guard revision != graphInputRevision else {
                install(staged.log, layout)
                finish()
                return true
            }
            revision = graphInputRevision
            layout = await layOut(graphInput(for: staged.log))
        }
        return false
    }

    /// Whether `staged` can still be published: no newer reload started, and
    /// for a page, the log it was built on is still the published one.
    private func isWanted(_ staged: StagedLog) -> Bool {
        staged.logGen == logGen && (staged.baseRevision.map { $0 == logRevision } ?? true)
    }

    /// Swaps in a fresh first page and its graph, laid out on the caller's
    /// actor. For tests and previews; the loaders `publish` instead, so the
    /// layout never runs on the main actor.
    func replaceLog(with page: [Commit]) {
        let staged = stageFirstPage(page)
        install(staged.log, CommitGraphEngine.layout(staged.input))
    }

    /// Appends the next page and publishes the graph with it, laid out on the
    /// caller's actor. For tests and previews, as `replaceLog(with:)`.
    func appendPage(_ page: [Commit]) {
        let staged = stageNextPage(page)
        install(staged.log, CommitGraphEngine.layout(staged.input))
    }

    private func install(_ log: HistoryLog, _ layout: GraphLayout) {
        commits = log.commits
        loadedRawCount = log.rawCount
        graphPageEnds = log.pageEnds
        loadedStashShas = log.stashShas
        apply(layout)
        logRevision &+= 1
        // Any recompute still running was computed for the previous log.
        graphLayoutGen &+= 1
    }

    /// What the engine lays out for the published log: its rows, pages and
    /// stashes, HEAD, the refs that name the lines and the size of the palette.
    func graphInput() -> GraphInput {
        graphInput(for: loadedLog)
    }

    private func graphInput(for log: HistoryLog) -> GraphInput {
        GraphInput(commits: log.commits,
                   pageEnds: log.pageEnds,
                   headSha: refsSource?.headSha,
                   refs: refsSource?.refs ?? [],
                   stashShas: log.stashShas,
                   paletteSize: graphPaletteSize)
    }

    /// Pool colours for the current accent (`LaneColors.pool(accent:).count`).
    /// The engine spreads ordinary lines over that many colours, so a new
    /// size recomputes the graph; the same size does nothing.
    func setGraphPaletteSize(_ size: Int) async {
        guard size != graphPaletteSize else { return }
        graphPaletteSize = size
        await recomputeGraph()
    }

    /// Lays the published log out again after something else the graph reads
    /// changed (refs, HEAD, palette). Runs off the main actor, so a reload
    /// over 50k commits doesn't stutter the scroll view, and lands only on
    /// the log it was computed for (see the gen-token contract above). A log
    /// still loading picks the change up when it is published.
    func recomputeGraph() async {
        graphInputRevision &+= 1
        await relayout()
    }

    private func relayout() async {
        graphLayoutGen &+= 1
        let gen = graphLayoutGen
        let input = graphInput()
        let layout = input.commits.isEmpty ? GraphLayout.empty : await layOut(input)
        guard gen == graphLayoutGen else { return }
        apply(layout)
    }

    private func layOut(_ input: GraphInput) async -> GraphLayout {
        let engine = graphEngine
        return await Task.detached { await engine(input) }.value
    }

    /// Synchronous variant used by SwiftUI previews and any caller that
    /// genuinely needs the graph populated before the next instruction.
    /// Production paths should prefer `recomputeGraph()` to keep the main
    /// actor free.
    func recomputeGraphSync() {
        graphLayoutGen &+= 1
        apply(CommitGraphEngine.layout(graphInput()))
    }

    private func apply(_ layout: GraphLayout) {
        graphLayouts = layout.rows
        graphMaxLanes = max(1, layout.columnCount)
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
