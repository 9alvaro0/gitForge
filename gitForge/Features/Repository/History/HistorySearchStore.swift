import Foundation
import Observation

/// History's git-backed search (#62): message, author, content and path criteria, run by
/// `git log` over the log's whole walk, not only the loaded pages. The instant filter in
/// the filters bar still dims the loaded rows; this one finds what isn't loaded yet.
///
/// Owned by `HistoryStore` (`viewModel.history.search`). Results come as a flat list: a
/// filtered walk skips the commits between two matches, so the graph's lines can't be
/// drawn for it. They page with the log's page size and `--skip`, and walk the scope the
/// graph was loaded with (`HistoryStore.searchScope()`), so any result can be revealed in
/// the graph (`jumpToGraph(_:)`).
///
/// One search at a time: a new query, Stop or Clear cancels the `git log` in flight
/// (`GitCLI.run` terminates the process), and a generation token drops whatever a
/// superseded search still returns.
@Observable
@MainActor
final class HistorySearchStore {
    /// What the chips show and edit. `run()` searches for it.
    var draft = HistorySearchQuery()
    /// The criteria shown as chips, in the order they were added. A chip stays while it is
    /// being typed into, even empty.
    private(set) var visibleFields: [HistorySearchQuery.Field] = []

    /// The query the results are for; nil while History shows the graph.
    private(set) var activeQuery: HistorySearchQuery?
    private(set) var results: [Commit] = []
    /// `results` by sha: `HistoryStore.selectedCommit` finds a selected result here when
    /// it isn't in the loaded log.
    private(set) var resultsById: [Commit.ID: Commit] = [:]
    /// The first page is being fetched.
    private(set) var isSearching = false
    /// A next page is being fetched.
    private(set) var isLoadingMore = false
    /// The last page came back full: there may be more matches.
    private(set) var hasMore = false
    /// The user stopped the search; `results` holds what came before.
    private(set) var isStopped = false
    /// A result is being revealed in the graph (`jumpToGraph(_:)`).
    private(set) var isJumping = false
    private(set) var error: String?

    /// Every tracked path and the folders above them, sorted; nil until read
    /// (`loadTrackedPaths()`).
    private(set) var trackedPaths: [String]?

    var isActive: Bool { activeQuery != nil }

    /// Raw commits fetched for `activeQuery`: the next page's `--skip`.
    @ObservationIgnored private var rawCount = 0
    /// The scope the results were fetched with; later pages walk it too.
    @ObservationIgnored private var scope: HistoryScope?
    /// Bumped by every search, stop and clear. A fetch writes only while its token is current.
    @ObservationIgnored private var gen: UInt64 = 0
    /// The fetch in flight (first page or next page): what Stop, Clear and a new query cancel.
    @ObservationIgnored private var task: Task<Void, Never>?
    /// The graph's selection when the search started, restored when it is cleared.
    @ObservationIgnored private var selectionBeforeSearch: Commit.ID?

    private let cli: GitCLI
    /// Selection, scope, page size and reveal. Set by `HistoryStore.init`.
    @ObservationIgnored weak var history: HistoryStore?

    init(cli: GitCLI) {
        self.cli = cli
    }

    // MARK: Entry points

    /// Lists only the commits whose author matches `author` across the whole history, as
    /// an author's "Only commits by …" menu item does. Sets the Author criterion (the
    /// other criteria stay) and runs the search. Pass the email for an exact match: the
    /// criterion is matched, ignoring case, as a substring of "Name <email>".
    func showCommits(byAuthor author: String) {
        draft.author = author
        show(.author)
        run()
    }

    /// Shows `field`'s chip, empty if it has no text yet.
    func show(_ field: HistorySearchQuery.Field) {
        guard !visibleFields.contains(field) else { return }
        visibleFields.append(field)
    }

    /// Removes `field`'s chip and its text. A search that was showing runs again without
    /// it, or ends when nothing is left.
    func remove(_ field: HistorySearchQuery.Field) {
        visibleFields.removeAll { $0 == field }
        draft[field] = ""
        if field == .content { draft.contentIsRegex = false }
        guard isActive else { return }
        if draft.isEmpty { clear() } else { run() }
    }

    /// Searches for `draft`, cancelling the search in flight. An empty draft clears the
    /// search instead.
    func run() {
        let query = draft.normalized
        guard !query.isEmpty else {
            clear()
            return
        }
        let gen = begin(query)
        task = Task { [weak self] in await self?.fetchFirstPage(query, gen: gen) }
    }

    /// Runs the active query again over the current scope (the log reloaded with another one).
    func rerun() {
        guard let activeQuery else { return }
        let gen = begin(activeQuery)
        task = Task { [weak self] in await self?.fetchFirstPage(activeQuery, gen: gen) }
    }

    /// Stops the `git log` in flight. The results so far stay, and the chips too.
    func stop() {
        guard isSearching || isLoadingMore else { return }
        cancelInFlight()
        isSearching = false
        isLoadingMore = false
        isStopped = true
    }

    /// Ends the search: the chips go, the graph comes back and its selection is the one it
    /// had when the search started (the first commit if that one left the log).
    func clear() {
        end(restoringSelection: true)
        draft = HistorySearchQuery()
        visibleFields = []
    }

    /// Fetches the next page when `currentItem` is the last result.
    func loadMoreIfNeeded(currentItem: Commit) {
        guard hasMore, !isSearching, !isLoadingMore, let query = activeQuery,
              results.last?.id == currentItem.id else { return }
        let gen = self.gen
        isLoadingMore = true
        task = Task { [weak self] in await self?.fetchNextPage(query, gen: gen) }
    }

    /// Selects `sha` in the graph, loading the log's pages down to it
    /// (`HistoryStore.revealCommit(_:)`), and ends the search, keeping that selection.
    /// False, with the search still showing, when the commit isn't in the graph's walk.
    @discardableResult
    func jumpToGraph(_ sha: String) async -> Bool {
        guard let history, !isJumping else { return false }
        isJumping = true
        defer { isJumping = false }
        guard await history.revealCommit(sha) else { return false }
        end(restoringSelection: false)
        draft = HistorySearchQuery()
        visibleFields = []
        return true
    }

    /// Waits for the fetch in flight, if any. Tests use it after `run()`.
    func waitForSearch() async {
        await task?.value
    }

    /// Drops everything when the session stops, like `HistoryStore.purge()`.
    func purge() {
        cancelInFlight()
        reset()
        draft = HistorySearchQuery()
        visibleFields = []
        selectionBeforeSearch = nil
        trackedPaths = nil
    }

    // MARK: Fetching

    /// Starts a search for `query`: cancels the one in flight, empties the results and
    /// remembers the graph's selection if no search was showing. Returns the new token.
    private func begin(_ query: HistorySearchQuery) -> UInt64 {
        if activeQuery == nil {
            selectionBeforeSearch = history?.selectedCommitId
        }
        cancelInFlight()
        reset()
        activeQuery = query
        scope = history?.searchScope()
        isSearching = true
        return gen
    }

    private func fetchFirstPage(_ query: HistorySearchQuery, gen: UInt64) async {
        let pageSize = history?.pageSize() ?? GitPreferences.commitPageSize
        do {
            let page = try await cli.searchLog(query, limit: pageSize, skip: 0, refs: revisions)
            guard gen == self.gen else { return }
            isSearching = false
            append(page, pageSize: pageSize)
            // Like the log's first page: the first result is selected, so the
            // inspector shows it and ↑ / ↓ start from it.
            if let first = results.first {
                history?.selectedCommitId = first.id
            }
        } catch {
            guard gen == self.gen else { return }
            isSearching = false
            if !(error is CancellationError) { self.error = error.userMessage }
        }
    }

    private func fetchNextPage(_ query: HistorySearchQuery, gen: UInt64) async {
        let pageSize = history?.pageSize() ?? GitPreferences.commitPageSize
        do {
            let page = try await cli.searchLog(query, limit: pageSize, skip: rawCount, refs: revisions)
            guard gen == self.gen else { return }
            isLoadingMore = false
            append(page, pageSize: pageSize)
        } catch {
            guard gen == self.gen else { return }
            isLoadingMore = false
            if !(error is CancellationError) { self.error = error.userMessage }
        }
    }

    /// The scope's revisions without its stashes: a stash's index and untracked commits
    /// are git plumbing the graph hides, and a filtered walk can't tell them apart from
    /// the stash they belong to. Stashes have their own list in the sidebar.
    private var revisions: [String] {
        guard let scope else { return ["HEAD"] }
        return scope.revisions.filter { !scope.stashShas.contains($0) }
    }

    /// Adds a page, skipping commits already listed (the log may have grown between two
    /// pages, which shifts `--skip`); `rawCount` still counts them.
    private func append(_ page: [Commit], pageSize: Int) {
        rawCount += page.count
        hasMore = page.count == pageSize
        for commit in page where resultsById[commit.id] == nil {
            results.append(commit)
            resultsById[commit.id] = commit
        }
    }

    private func cancelInFlight() {
        task?.cancel()
        task = nil
        gen &+= 1
    }

    private func reset() {
        activeQuery = nil
        results = []
        resultsById = [:]
        rawCount = 0
        scope = nil
        hasMore = false
        isSearching = false
        isLoadingMore = false
        isStopped = false
        error = nil
    }

    private func end(restoringSelection: Bool) {
        let wasActive = isActive
        let previous = selectionBeforeSearch
        cancelInFlight()
        reset()
        selectionBeforeSearch = nil
        if wasActive, restoringSelection {
            history?.restoreSelection(previous)
        }
    }

    // MARK: Path completion

    /// Reads the tracked paths for the Path criterion's completion. Read again each time
    /// the chip is shown, so new files are offered; off the main actor for a large index.
    func loadTrackedPaths() async {
        guard let files = try? await cli.trackedFiles() else { return }
        trackedPaths = await Task.detached { Self.pathsWithFolders(files) }.value
    }

    /// `files` and every folder above them (with a trailing `/`), sorted.
    nonisolated static func pathsWithFolders(_ files: [String]) -> [String] {
        var paths = Set(files)
        for file in files {
            var folder = Substring(file)
            while let slash = folder.lastIndex(of: "/") {
                folder = folder[..<slash]
                guard paths.insert(String(folder) + "/").inserted else { break }
            }
        }
        return paths.sorted()
    }

    /// Up to `limit` of `paths` that contain `text`, ignoring case: the ones that start
    /// with it first, then shorter before longer. Nothing for empty text or when the
    /// only match is `text` itself.
    nonisolated static func pathSuggestions(for text: String, in paths: [String], limit: Int = 8) -> [String] {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        var prefixed: [String] = []
        var containing: [String] = []
        for path in paths where path != needle {
            guard let range = path.range(of: needle, options: .caseInsensitive) else { continue }
            if range.lowerBound == path.startIndex {
                prefixed.append(path)
            } else {
                containing.append(path)
            }
        }
        func shortestFirst(_ a: String, _ b: String) -> Bool {
            a.count != b.count ? a.count < b.count : a < b
        }
        return Array((prefixed.sorted(by: shortestFirst) + containing.sorted(by: shortestFirst)).prefix(limit))
    }
}
