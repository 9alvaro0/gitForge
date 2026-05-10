import Foundation

extension RepositoryViewModel {
    func selectStash(_ stash: Stash) {
        selectedStash = stash
        stashDetail = nil
        stashDetailError = nil
        selectedStashFile = nil
        stashFileDiff = []
        Task { await loadStashDetail() }
    }

    func closeStashDetail() {
        selectedStash = nil
        stashDetail = nil
        stashDetailError = nil
        selectedStashFile = nil
        stashFileDiff = []
    }

    func loadStashDetail() async {
        guard let stash = selectedStash else { return }
        stashDetailLoading = true
        defer { stashDetailLoading = false }
        do {
            async let parent = cli.stashParent(index: stash.index)
            async let files = cli.stashFiles(index: stash.index)
            let (p, f) = try await (parent, files)
            stashDetail = StashDetail(
                stash: stash,
                parentSha: p.parentSha,
                parentBranch: stash.parentBranch,
                authorDate: p.authorDate,
                files: f
            )
            stashDetailError = nil
            // Auto-select the first file so the diff pane has content as soon
            // as the detail lands, mirroring CommitDetail's UX.
            if let first = f.first {
                await loadStashFileDiff(at: first.path)
            }
        } catch {
            stashDetailError = error.userMessage
        }
    }

    func loadStashFileDiff(at path: String) async {
        guard let stash = selectedStash else { return }
        selectedStashFile = path
        loadingStashFileDiff = true
        defer { loadingStashFileDiff = false }
        do {
            let raw = try await cli.stashFileDiff(index: stash.index, path: path)
            stashFileDiff = DiffParser.parse(raw)
            stashFileDiffEmptyState = .empty
        } catch {
            stashFileDiff = []
            stashFileDiffEmptyState = .empty
        }
    }
}
