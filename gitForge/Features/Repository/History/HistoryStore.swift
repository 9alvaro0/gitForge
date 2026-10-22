import Foundation
import Observation

/// The session's refs as the graph sees them. `RepositoryViewModel` owns
/// them (`loadRefs`) and conforms; the history store reads them to build the
/// graph scope and writes back the fresh stashes / unmerged branches it reads
/// alongside each first page, so the scope and the page always match. The
/// first page also seeds the refs when none were read yet.
@MainActor
protocol HistoryRefsSource: AnyObject {
    var stashes: [Stash] { get set }
    var unmergedLocalBranchRefs: [String] { get set }
    var refsBySha: [String: [GitRef]] { get }
    /// Every ref, as `GitCLI.refs()` returns them: the graph names its lines from these.
    var refs: [GitRef] { get set }
    /// Branch each remote's HEAD points at (`GitCLI.remoteHeads()`): picks the remote trunk.
    var remoteHeads: [String: String] { get set }
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
    /// (`publish(_:then:)`); only tests and previews set it directly, usually
    /// through the hooks in `HistoryStore+Preview.swift`.
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
    /// The scope the published log was fetched with; nil before the first one.
    /// Its later pages are fetched with it too, never with the current scope.
    private(set) var loadedScope: HistoryScope?
    /// Bumped each time a log is published or purged. An append staged on an
    /// older log is dropped instead of landing on rows it wasn't fetched for.
    private(set) var logRevision: UInt64 = 0
    /// Raw commits per `git log` page, read by every loader when it starts. A
    /// test seam, like `graphEngine`: tests set a small page without touching
    /// the user's preferences; no production code assigns it.
    @ObservationIgnored var pageSize: () -> Int = { GitPreferences.commitPageSize }
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
    /// Columns the graph assigns, reserved ones included
    /// (`GraphLayout.columnCount`), at least 1.
    var graphMaxLanes: Int = 1
    /// The refs drawn as chips, published with the layout they came with: made from the
    /// refs and remote trunks that layout was laid out with and from the toggle of the
    /// loaded scope, so chips and graph never disagree (§4.4).
    private(set) var refChips: HistoryRefChips = .empty
    /// What `refChips` was made from. `apply` keeps the chips while the refs, the remote
    /// trunks and the toggle are the same, so a page or a palette change costs nothing here.
    /// Tests read it to check that its refs share the published ones' storage.
    @ObservationIgnored private(set) var refChipsSource: RefChipsSource?
    struct RefChipsSource: Equatable {
        let refs: [GitRef]
        let remoteTrunks: [String: Int]
        let includesAllRemotes: Bool
    }
    /// Builds the chips. A test seam, like `graphEngine`: tests swap it to count builds.
    @ObservationIgnored var refChipsBuilder: ([GitRef], [String: Int], Bool) -> HistoryRefChips = {
        HistoryRefChips.make(refs: $0, remoteTrunks: $1, includesAllRemotes: $2)
    }
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
    /// Lays a graph out, always off the main actor. A test seam: the race
    /// tests swap it to hold a pass and interleave it with another; no
    /// production code assigns it.
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
    private let repositoryURL: URL
    private let defaults: UserDefaults
    @ObservationIgnored weak var refsSource: (any HistoryRefsSource)?

    init(cli: GitCLI, tasks: OwnedTasks, repositoryURL: URL, defaults: UserDefaults = .standard) {
        self.cli = cli
        self.tasks = tasks
        self.repositoryURL = repositoryURL
        self.defaults = defaults
        showsRemoteBranches = defaults.bool(forKey: Self.remoteBranchesKey(for: repositoryURL))
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
        loadedScope = nil
        graphLayouts = []
        graphMaxLanes = 1
        refChips = .empty
        refChipsSource = nil
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

    /// Every remote branch is in the graph (§4.2), not only the ones local branches
    /// track. Remembered per repository (`setShowsRemoteBranches(_:)`).
    private(set) var showsRemoteBranches: Bool

    /// "gitForge.history.remoteBranches.<standardized path>", like `WorkingCopyStore.signOffKey(for:)`.
    static func remoteBranchesKey(for repositoryURL: URL) -> String {
        "gitForge.history.remoteBranches.\(repositoryURL.standardizedFileURL.path(percentEncoded: false))"
    }

    /// Stores the choice and reloads the log with the new scope. The same value does
    /// nothing.
    func setShowsRemoteBranches(_ on: Bool) async {
        guard on != showsRemoteBranches else { return }
        showsRemoteBranches = on
        defaults.set(on, forKey: Self.remoteBranchesKey(for: repositoryURL))
        await reloadLog()
    }

    /// The scope the next first page is fetched with, from the refs as they
    /// are now (§3.1): HEAD, local branches not merged into it, what a pull
    /// would bring, the remote trunk, tags and stashes, and every remote
    /// branch with `showsRemoteBranches` (`HistoryScope.make`).
    /// The stash set a log is fetched with is the one it keeps
    /// (`HistoryLog.stashShas`), even if the live list changes meanwhile.
    func currentScope() -> HistoryScope {
        let refs = refsSource?.refs ?? []
        return HistoryScope.make(refs: refs,
                                 unmergedLocalBranchRefs: refsSource?.unmergedLocalBranchRefs ?? [],
                                 stashes: stashes,
                                 remoteTrunks: remoteTrunks(in: refs),
                                 includesAllRemotes: showsRemoteBranches)
    }

    /// `currentScope().revisions`.
    func graphScope() -> [String] {
        currentScope().revisions
    }

    /// The published log no longer loads what the current refs ask for: a
    /// remote branch in its scope moved, came or went
    /// (`HistoryScope.isOutdated(by:)`). False before the first log.
    var isScopeStale: Bool {
        loadedScope?.isOutdated(by: currentScope()) ?? false
    }

    /// Remote branches standing in for a missing local trunk, for the scope
    /// and the graph alike.
    private func remoteTrunks(in refs: [GitRef]) -> [String: Int] {
        GraphTrunks.remoteStandIns(refs: refs, remoteHeads: refsSource?.remoteHeads ?? [:])
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
    //   • A log is published with the scope it was fetched with
    //     (`loadedScope`), and its pages are fetched with that scope, not
    //     the current one: `--skip` only means something on the same walk.
    //     When the current scope moves away from it (`isScopeStale`), the
    //     view model reloads the log.
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
        let pageSize = self.pageSize()
        do {
            // Stashes, unmerged-branch refs and the refs feed currentScope();
            // without them the first page walks an incomplete scope (no
            // remote branches) and jumps when the log reloads. Read in
            // parallel the ones no earlier loadRefs() seeded. The refs without
            // tags: neither the scope nor the graph needs them, and in a repo
            // with thousands of tags they would hold the first page back.
            let needsStashes = stashes.isEmpty
            let needsUnmerged = refsSource?.unmergedLocalBranchRefs.isEmpty ?? true
            let needsRefs = refsSource?.refs.isEmpty ?? true
            if needsStashes || needsUnmerged || needsRefs {
                async let stashTask: [Stash]? = needsStashes ? try? cli.stashes() : nil
                async let unmergedTask: [String]? = needsUnmerged ? try? cli.unmergedLocalBranches() : nil
                async let refsTask: [GitRef]? = needsRefs ? try? cli.refs(includingTags: false) : nil
                async let remoteHeadsTask: [String: String]? = needsRefs ? try? cli.remoteHeads() : nil
                let (freshStashes, freshUnmerged, freshRefs, freshRemoteHeads)
                    = await (stashTask, unmergedTask, refsTask, remoteHeadsTask)
                guard gen == logGen else { return }
                // Seeds only: what a loadRefs() that landed meanwhile wrote stays,
                // tags included. The one that lands later brings the tags, and its
                // refs differ from these, so it lays the published log out again.
                if let freshStashes, stashes.isEmpty {
                    refsSource?.stashes = freshStashes
                }
                if let freshUnmerged, let source = refsSource, source.unmergedLocalBranchRefs.isEmpty {
                    source.unmergedLocalBranchRefs = freshUnmerged
                }
                if let freshRefs, let source = refsSource, source.refs.isEmpty {
                    source.refs = freshRefs
                    source.remoteHeads = freshRemoteHeads ?? [:]
                    // The graph reads the refs: a log being laid out without
                    // them lays itself out again (gen-token contract).
                    await recomputeGraph()
                    guard gen == logGen else { return }
                }
            }
            let scope = currentScope()
            let page = try await cli.log(limit: pageSize, skip: 0, refs: scope.revisions)
            guard gen == logGen else { return }
            await publish(stageFirstPage(page, scope: scope, logGen: gen)) {
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
    /// With `keepingDepth`, for a reload the user didn't ask for (a fetch
    /// moved a remote branch of the scope), it refetches as many raw commits
    /// as are loaded, at least a page, in one walk, and splits them into pages
    /// (`HistoryLog.paged`): the log the user had after scrolling as far, so
    /// the rows they were looking at and the selection on them stay.
    ///
    /// Preserves the user's selection when the previously-selected commit
    /// is still in the new log; otherwise falls back to the new first
    /// commit (matching `loadInitial`'s default).
    func reloadLog(keepingDepth: Bool = false) async {
        let previousSelection = selectedCommitId
        logGen &+= 1
        let gen = logGen
        loadError = nil
        let pageSize = self.pageSize()
        let limit = keepingDepth ? max(pageSize, loadedRawCount) : pageSize
        do {
            async let stashTask = cli.stashes()
            async let unmergedTask = cli.unmergedLocalBranches()
            let freshStashes = (try? await stashTask) ?? []
            let freshUnmerged = (try? await unmergedTask) ?? []
            guard gen == logGen else { return }
            refsSource?.stashes = freshStashes
            refsSource?.unmergedLocalBranchRefs = freshUnmerged
            let scope = currentScope()
            let raw = try await cli.log(limit: limit, skip: 0, refs: scope.revisions)
            guard gen == logGen else { return }
            // Each page of the split goes over the rows before it: off the main actor for a deep log.
            let log = raw.count > pageSize
                ? await Task.detached { HistoryLog.paged(raw, pageSize: pageSize, stashShas: scope.stashShas) }.value
                : HistoryLog.firstPage(raw, stashShas: scope.stashShas)
            guard gen == logGen else { return }
            await publish(stage(log, scope: scope, logGen: gen, baseRevision: nil)) {
                hasMore = raw.count == limit
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
        let pageSize = self.pageSize()
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
    ///
    /// The page walks what the log's first page walked (`loadedScope`), even
    /// if a fetch has moved a remote branch since: on another walk, `--skip`
    /// would jump over commits or repeat them.
    private func paginateNextPage(gen: UInt64, pageSize: Int) async throws -> [Commit]? {
        let base = logRevision
        let scope = loadedScope ?? currentScope()
        let next = try await cli.log(limit: pageSize, skip: loadedRawCount, refs: scope.revisions)
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
        /// The scope `log` was fetched with; `install` keeps it as `loadedScope`.
        let scope: HistoryScope
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

    /// A log that starts over with `page`. Defaults are for tests: the
    /// current scope and `logGen`; the loaders pass the scope the page was
    /// fetched with and their own token.
    func stageFirstPage(_ page: [Commit], scope: HistoryScope? = nil, logGen gen: UInt64? = nil) -> StagedLog {
        let scope = scope ?? currentScope()
        return stage(HistoryLog.firstPage(page, stashShas: scope.stashShas), scope: scope,
                     logGen: gen ?? logGen, baseRevision: nil)
    }

    /// The published log with `page` appended (`HistoryLog.appending`); it
    /// keeps the log's scope. Defaults are for tests: the live stashes and
    /// the current `logGen` and revision; the loader passes the stashes of
    /// the scope it fetched with and the revision it fetched against.
    func stageNextPage(_ page: [Commit], scopeStashShas: Set<String>? = nil, logGen gen: UInt64? = nil,
                       baseRevision: UInt64? = nil) -> StagedLog {
        let log = loadedLog.appending(page, scopeStashShas: scopeStashShas ?? Set(stashes.map(\.sha)))
        return stage(log, scope: loadedScope ?? currentScope(), logGen: gen ?? logGen,
                     baseRevision: baseRevision ?? logRevision)
    }

    private func stage(_ log: HistoryLog, scope: HistoryScope, logGen gen: UInt64, baseRevision: UInt64?) -> StagedLog {
        StagedLog(log: log, scope: scope, input: graphInput(for: log, scope: scope), logGen: gen,
                  baseRevision: baseRevision, inputRevision: graphInputRevision)
    }

    /// Lays `staged` out off the main actor, then publishes the log and its
    /// graph in one main-actor turn: `commits`, `loadedRawCount`,
    /// `graphPageEnds`, `loadedStashShas`, `loadedScope`, `graphLayouts`,
    /// `graphMaxLanes` and `refChips`, followed by `finish`, the caller's own
    /// state that goes with this log (`hasMore`, the selection…). Nothing is
    /// awaited between the install and `finish`, so a newer load can't publish
    /// in between and be overwritten.
    ///
    /// If refs, HEAD or the palette changed during a pass (a recompute was
    /// asked for), the log is laid out again from the current ones before
    /// anything is shown, as many times as it takes. Returns false, running
    /// nothing, when a newer reload superseded it or (for a page) another log
    /// was published since its base.
    @discardableResult
    func publish(_ staged: StagedLog, then finish: @MainActor () -> Void = {}) async -> Bool {
        var revision = staged.inputRevision
        var input = staged.input
        var layout = await layOut(input)
        while isWanted(staged) {
            guard revision != graphInputRevision else {
                install(staged, layout, from: input)
                finish()
                return true
            }
            revision = graphInputRevision
            input = graphInput(for: staged.log, scope: staged.scope)
            layout = await layOut(input)
        }
        return false
    }

    /// Whether `staged` can still be published: no newer reload started, and
    /// for a page, the log it was built on is still the published one.
    private func isWanted(_ staged: StagedLog) -> Bool {
        staged.logGen == logGen && (staged.baseRevision.map { $0 == logRevision } ?? true)
    }

    /// Installs the staged log, its scope and `layout` (laid out from `input`)
    /// as the published ones, in one main-actor turn. The loaders reach it
    /// through `publish`, which lays the log out off the main actor first;
    /// previews call it directly, through the hooks in `HistoryStore+Preview.swift`.
    func install(_ staged: StagedLog, _ layout: GraphLayout, from input: GraphInput) {
        let log = staged.log
        commits = log.commits
        loadedRawCount = log.rawCount
        graphPageEnds = log.pageEnds
        loadedStashShas = log.stashShas
        loadedScope = staged.scope
        apply(layout, from: input)
        logRevision &+= 1
        // Any recompute still running was computed for the previous log.
        graphLayoutGen &+= 1
    }

    /// What the engine lays out for the published log: its rows, pages and
    /// stashes, HEAD, the refs that name the lines, the remote trunks and
    /// the size of the palette.
    func graphInput() -> GraphInput {
        graphInput(for: loadedLog, scope: loadedScope)
    }

    /// The input for `log`, fetched with `scope`. Its remote branches stay at
    /// the tips the log was loaded with (`HistoryScope.pinning`): after a fetch
    /// moved one, the log is laid out again before it reloads, and with the new
    /// tip, which it may not have, the commits it loaded for that branch would
    /// lose their name, column and ghost look until then. The chips follow.
    private func graphInput(for log: HistoryLog, scope: HistoryScope?) -> GraphInput {
        let live = refsSource?.refs ?? []
        let refs = scope?.pinning(live) ?? live
        return GraphInput(commits: log.commits,
                          pageEnds: log.pageEnds,
                          headSha: refsSource?.headSha,
                          refs: refs,
                          stashShas: log.stashShas,
                          paletteSize: graphPaletteSize,
                          remoteTrunks: remoteTrunks(in: refs))
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
        apply(layout, from: input)
    }

    private func layOut(_ input: GraphInput) async -> GraphLayout {
        let engine = graphEngine
        return await Task.detached { await engine(input) }.value
    }

    /// Shows `layout`'s rows and column count, and the chips of the `input` it was
    /// laid out from: the last step of `install` and `relayout`, and of the
    /// synchronous hook in `HistoryStore+Preview.swift`. The chips follow the
    /// toggle of the loaded scope, not the live one: a log fetched without the
    /// remote branches has none of them to label.
    func apply(_ layout: GraphLayout, from input: GraphInput) {
        graphLayouts = layout.rows
        graphMaxLanes = max(1, layout.columnCount)
        let source = RefChipsSource(refs: input.refs, remoteTrunks: input.remoteTrunks,
                                    includesAllRemotes: loadedScope?.includesAllRemotes ?? false)
        // O(1) while the refs share the source's storage, element by element otherwise. Kept
        // even when equal, so after refs read again into a new buffer only the first page or
        // relayout pays for the element-wise compare.
        let changed = source != refChipsSource
        refChipsSource = source
        guard changed else { return }
        refChips = refChipsBuilder(source.refs, source.remoteTrunks, source.includesAllRemotes)
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
