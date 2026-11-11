import Foundation
import Observation

/// "File history": the commits that touched one file on HEAD, newest first
/// and across renames, paged like History, and the selected commit's diff
/// of that file alone. One per sheet, so History's own selection and caches
/// are left alone.
@Observable
@MainActor
final class FileHistoryStore {
    /// The file as the user picked it (its current path).
    let path: String

    private(set) var entries: [FileHistoryEntry] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var hasLoaded = false
    /// The last page came back full: there may be older commits.
    private(set) var hasMore = false
    private(set) var loadError: String?

    private(set) var selectedEntryId: FileHistoryEntry.ID?
    private(set) var fileDiff: [DiffHunk] = []
    private(set) var fileDiffEmptyState: DiffEmptyState = .empty
    private(set) var isLoadingFileDiff = false

    /// Bumped by every list load; a page that lands after a reload is dropped.
    private var listGen: UInt64 = 0
    /// Same contract for the diff of the selected entry.
    private var diffGen: UInt64 = 0

    private let cli: GitCLI
    /// Commits per `git log` page, read on every load. A test seam: tests
    /// set a small page without touching the user's preferences.
    @ObservationIgnored var pageSize: () -> Int = { GitPreferences.commitPageSize }

    init(cli: GitCLI, path: String) {
        self.cli = cli
        self.path = path
    }

    var selectedEntry: FileHistoryEntry? {
        guard let selectedEntryId else { return nil }
        return entries.first { $0.id == selectedEntryId }
    }

    /// The renames along the history, newest first: each entry that renamed
    /// the file, so the header can say what it was called before.
    var renames: [FileHistoryEntry] {
        entries.filter { if case .renamed = $0.status { true } else { false } }
    }

    // MARK: List

    /// Reads the first page and selects `sha`'s entry if it's on it, else
    /// the newest. Keeps the selection on a reload when it is still listed.
    func load(selecting sha: String? = nil) async {
        listGen &+= 1
        let gen = listGen
        let keep = sha ?? selectedEntryId
        isLoading = true
        defer { if gen == listGen { isLoading = false } }
        let size = pageSize()
        do {
            let page = try await cli.fileHistory(path: path, limit: size)
            guard gen == listGen else { return }
            entries = page
            hasMore = page.count == size
            loadError = nil
            hasLoaded = true
            let selection = keep.flatMap { id in page.first { $0.id == id } } ?? page.first
            await select(selection)
        } catch {
            guard gen == listGen else { return }
            entries = []
            hasMore = false
            hasLoaded = true
            loadError = error.userMessage
            await select(nil)
        }
    }

    /// Reads the next page when `entry` is the last one listed. The walk
    /// starts over from HEAD with a page more (`GitCLI.fileHistory` says
    /// why); only the commits after the listed ones are added.
    func loadMoreIfNeeded(after entry: FileHistoryEntry) async {
        guard hasMore, !isLoadingMore, entries.last?.id == entry.id else { return }
        let gen = listGen
        isLoadingMore = true
        defer { isLoadingMore = false }
        let limit = entries.count + pageSize()
        do {
            let walk = try await cli.fileHistory(path: path, limit: limit)
            guard gen == listGen else { return }
            let known = Set(entries.map(\.id))
            entries += walk.dropFirst(entries.count).filter { !known.contains($0.id) }
            hasMore = walk.count == limit
        } catch {
            guard gen == listGen else { return }
            loadError = error.userMessage
        }
    }

    // MARK: Selection

    /// Selects `entry` and loads the file's diff in that commit.
    func select(_ entry: FileHistoryEntry?) async {
        guard entry?.id != selectedEntryId || entry == nil else { return }
        selectedEntryId = entry?.id
        await loadDiff()
    }

    /// Re-reads the open diff (Hide whitespace flipped).
    func reloadFileDiff() async {
        await loadDiff()
    }

    private func loadDiff() async {
        diffGen &+= 1
        let gen = diffGen
        fileDiff = []
        fileDiffEmptyState = .empty
        guard let entry = selectedEntry else {
            isLoadingFileDiff = false
            return
        }
        isLoadingFileDiff = true
        defer { if gen == diffGen { isLoadingFileDiff = false } }
        do {
            let raw = try await cli.fileHistoryDiff(sha: entry.commit.sha, path: entry.path,
                                                    previousPath: entry.previousPath)
            guard gen == diffGen else { return }
            fileDiff = DiffParser.parse(raw)
            fileDiffEmptyState = fileDiff.isEmpty
                ? DiffEmptyState.classifying(raw: raw, ignoringWhitespace: GitPreferences.diffIgnoreWhitespace)
                : .empty
        } catch {
            guard gen == diffGen else { return }
            fileDiff = []
            fileDiffEmptyState = .empty
        }
    }

    /// The file at the selected commit, for "Show N hidden lines". `nil`
    /// for a deletion: there is no file on the new side.
    func newSideLines() async -> [String]? {
        guard let entry = selectedEntry, !entry.isDeletion else { return nil }
        return await cli.fileLines(revision: entry.commit.sha, path: entry.path)
    }
}
