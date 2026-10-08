import Foundation
import Observation

/// The stash detail pane: which stash is open, its metadata and files, and
/// the diff of the selected file. Owned by `RepositoryViewModel`
/// (`viewModel.stashDetail`). The stash *list* and the mutating operations
/// (apply / pop / drop / push) stay on the view model — they feed the graph
/// and refresh the whole session.
///
/// Everything is read by the stash's commit SHA: `stash@{n}` indices shift
/// when stashes are pushed or dropped, which made an open pane silently show
/// a different stash's files.
@Observable
@MainActor
final class StashDetailStore {
    var selected: Stash?
    var detail: StashDetail?
    var isLoading = false
    var error: String?
    var selectedFile: String?
    var fileDiff: [DiffHunk] = []
    var isLoadingFileDiff = false
    var fileDiffEmptyState: DiffEmptyState = .empty
    /// Bumped by every detail op (`select` / `close` / `load`); post-await
    /// writes are dropped if it moved, so a slow stash#0 fetch can't paint
    /// over a freshly-selected stash#1 (or onto a closed pane).
    var detailGen: UInt64 = 0
    /// Same contract for the file-diff pane.
    var fileDiffGen: UInt64 = 0

    private let cli: GitCLI
    private var loadTask: Task<Void, Never>?

    init(cli: GitCLI) {
        self.cli = cli
    }

    /// Open the pane for `stash` and start loading its parent + files.
    func select(_ stash: Stash) {
        detailGen &+= 1
        fileDiffGen &+= 1
        selected = stash
        clearContent()
        loadTask?.cancel()
        loadTask = Task { [weak self] in await self?.load() }
    }

    /// Close the pane. The invalidated loaders won't clear their own flags
    /// (their gen moved), so they're reset here.
    func close() {
        detailGen &+= 1
        fileDiffGen &+= 1
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
        isLoadingFileDiff = false
        selected = nil
        clearContent()
    }

    func load() async {
        detailGen &+= 1
        let gen = detailGen
        guard let stash = selected else { return }
        isLoading = true
        defer { if gen == detailGen { isLoading = false } }
        do {
            async let parent = cli.stashParent(sha: stash.sha)
            async let files = cli.stashFiles(sha: stash.sha)
            let (p, f) = try await (parent, files)
            guard gen == detailGen else { return }
            detail = StashDetail(
                stash: stash,
                parentSha: p.parentSha,
                parentBranch: stash.parentBranch,
                authorDate: p.authorDate,
                files: f
            )
            error = nil
            // Auto-select the first file so the diff pane has content as
            // soon as the detail lands, mirroring CommitDetail's UX. The
            // nested call snapshots its own `fileDiffGen`, so a fresher
            // selection still wins.
            if let first = f.first {
                await loadFileDiff(at: first.path)
            }
        } catch {
            guard gen == detailGen else { return }
            self.error = error.userMessage
        }
    }

    func loadFileDiff(at path: String) async {
        guard let stash = selected else { return }
        fileDiffGen &+= 1
        let gen = fileDiffGen
        selectedFile = path
        isLoadingFileDiff = true
        defer { if gen == fileDiffGen { isLoadingFileDiff = false } }
        do {
            let isUntracked = detail?.files.first(where: { $0.path == path })?.status == .untracked
            let raw = try await cli.stashFileDiff(sha: stash.sha, path: path, untracked: isUntracked)
            guard gen == fileDiffGen else { return }
            fileDiff = DiffParser.parse(raw)
            fileDiffEmptyState = fileDiff.isEmpty ? DiffEmptyState.classifying(raw: raw) : .empty
        } catch {
            guard gen == fileDiffGen else { return }
            fileDiff = []
            fileDiffEmptyState = .empty
        }
    }

    private func clearContent() {
        detail = nil
        error = nil
        selectedFile = nil
        fileDiff = []
        fileDiffEmptyState = .empty
    }
}
