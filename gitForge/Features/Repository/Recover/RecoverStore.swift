import Foundation
import Observation

/// "Recover lost commits": a ref's reflog, newest first, and the detail and
/// diff of the selected entry's commit. One per sheet, so History's own
/// selection and caches are left alone. The actions on an entry (create a
/// branch, check out, reset) run on `RepositoryViewModel`, which refreshes
/// the session; the sheet then calls `reload()`.
@Observable
@MainActor
final class RecoverStore {
    /// Whose reflog is listed.
    enum Source: Hashable, Sendable {
        case head
        /// A local branch, by its short name.
        case branch(String)

        var ref: String {
            switch self {
            case .head: "HEAD"
            case .branch(let name): "refs/heads/\(name)"
            }
        }
    }

    private(set) var source: Source = .head
    private(set) var entries: [ReflogEntry] = []
    /// Commits only this entry's commit brings back (no ref reaches them),
    /// by SHA. Empty when that couldn't be worked out.
    private(set) var lostCounts: [String: Int] = [:]
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var loadError: String?

    private(set) var selectedEntryId: ReflogEntry.ID?
    private(set) var detail: CommitDetail?
    private(set) var isLoadingDetail = false
    private(set) var selectedFile: String?
    private(set) var fileDiff: [DiffHunk] = []
    private(set) var fileDiffEmptyState: DiffEmptyState = .empty
    private(set) var isLoadingFileDiff = false

    /// Bumped by every list load; post-await writes are dropped if it moved,
    /// so HEAD's reflog can't land after the user picked a branch.
    private var listGen: UInt64 = 0
    /// Same contract for the detail and for the file diff.
    private var detailGen: UInt64 = 0
    private var fileDiffGen: UInt64 = 0

    private let cli: GitCLI
    private let limit: Int

    init(cli: GitCLI, limit: Int = GitCLI.reflogLimit) {
        self.cli = cli
        self.limit = limit
    }

    var selectedEntry: ReflogEntry? {
        guard let selectedEntryId else { return nil }
        return entries.first { $0.id == selectedEntryId }
    }

    /// How many commits recovering `entry` brings back; 0 when it's on a
    /// branch or tag already, `nil` when unknown.
    func lostCount(of entry: ReflogEntry) -> Int? {
        lostCounts[entry.commit.sha]
    }

    // MARK: List

    /// Lists `source`'s reflog, keeping the selection on the same entry
    /// if it's still there (a new entry on top shifts every index), else
    /// selecting the newest: after a reset, the state before it.
    func load(_ source: Source) async {
        let sourceChanged = source != self.source
        self.source = source
        listGen &+= 1
        let gen = listGen
        let previous = sourceChanged ? nil : selectedEntry
        isLoading = true
        defer { if gen == listGen { isLoading = false } }
        do {
            let loaded = try await cli.reflog(of: source.ref, limit: limit)
            guard gen == listGen else { return }
            entries = loaded
            loadError = nil
            hasLoaded = true
            lostCounts = [:]
            let keep = previous.flatMap { old in loaded.first { Self.sameMove($0, old) } }
            await select(keep ?? loaded.first)
            guard gen == listGen else { return }
            await loadLostCounts(gen: gen)
        } catch {
            guard gen == listGen else { return }
            entries = []
            lostCounts = [:]
            hasLoaded = true
            loadError = error.userMessage
            await select(nil)
        }
    }

    /// Reads the list again (after an action moved HEAD or a branch).
    func reload() async {
        await load(source)
    }

    /// Best effort: a reflog pointing at a commit `gc` already pruned makes
    /// `rev-list` fail, and the list is still worth showing without counts.
    private func loadLostCounts(gen: UInt64) async {
        let shas = entries.map(\.commit.sha)
        guard let unreachable = try? await cli.unreachableCommits(from: shas), gen == listGen else { return }
        lostCounts = ReflogRecovery.lostCounts(for: shas, unreachable: unreachable)
    }

    /// The same move of the ref, whatever its index now.
    private static func sameMove(_ a: ReflogEntry, _ b: ReflogEntry) -> Bool {
        a.movedTo.sha == b.movedTo.sha && a.date == b.date && a.message == b.message
            && a.commit.sha == b.commit.sha
    }

    // MARK: Selection

    /// Selects `entry` and loads its commit's detail, then the first file's
    /// diff. Selecting another entry on the same commit keeps what's open.
    func select(_ entry: ReflogEntry?) async {
        let sameCommit = entry != nil && entry?.commit.sha == detail?.commit.sha
        selectedEntryId = entry?.id
        guard !sameCommit else { return }
        detailGen &+= 1
        fileDiffGen &+= 1
        let gen = detailGen
        detail = nil
        selectedFile = nil
        fileDiff = []
        fileDiffEmptyState = .empty
        isLoadingFileDiff = false
        guard let commit = entry?.commit else {
            isLoadingDetail = false
            return
        }
        isLoadingDetail = true
        defer { if gen == detailGen { isLoadingDetail = false } }
        guard let loaded = try? await cli.commitDetail(for: commit), gen == detailGen else { return }
        detail = loaded
        if let first = loaded.files.first {
            await selectFile(first.path)
        }
    }

    func selectFile(_ path: String) async {
        guard let sha = selectedEntry?.commit.sha else { return }
        fileDiffGen &+= 1
        let gen = fileDiffGen
        selectedFile = path
        isLoadingFileDiff = true
        defer { if gen == fileDiffGen { isLoadingFileDiff = false } }
        do {
            let raw = try await cli.diff(sha: sha, file: path)
            guard gen == fileDiffGen else { return }
            fileDiff = DiffParser.parse(raw)
            fileDiffEmptyState = fileDiff.isEmpty
                ? DiffEmptyState.classifying(raw: raw, ignoringWhitespace: GitPreferences.diffIgnoreWhitespace)
                : .empty
        } catch {
            guard gen == fileDiffGen else { return }
            fileDiff = []
            fileDiffEmptyState = .empty
        }
    }

    /// Re-reads the open file's diff (Hide whitespace flipped).
    func reloadFileDiff() async {
        guard let path = selectedFile else { return }
        await selectFile(path)
    }

    /// The open file at the selected commit, for "Show N hidden lines".
    func newSideLines() async -> [String]? {
        guard let sha = selectedEntry?.commit.sha, let path = selectedFile else { return nil }
        return await cli.fileLines(revision: sha, path: path)
    }
}
