import Foundation

extension RepositoryViewModel {
    /// Open the detail view for `stash` and kick off the parallel fetch of
    /// parent + files. Bumps `stashDetailGen` so a load triggered by a
    /// previous selection drops its writes when it resumes.
    func selectStash(_ stash: Stash) {
        stashDetailGen &+= 1
        selectedStash = stash
        stashDetail = nil
        stashDetailError = nil
        selectedStashFile = nil
        stashFileDiff = []
        track(Task { [weak self] in await self?.loadStashDetail() })
    }

    /// Close the detail view and bump the gen-token so an in-flight load
    /// can't paint into a now-closed pane.
    func closeStashDetail() {
        stashDetailGen &+= 1
        selectedStash = nil
        stashDetail = nil
        stashDetailError = nil
        selectedStashFile = nil
        stashFileDiff = []
    }

    func loadStashDetail() async {
        stashDetailGen &+= 1
        let gen = stashDetailGen
        guard let stash = selectedStash else { return }
        stashDetailLoading = true
        defer { if gen == stashDetailGen { stashDetailLoading = false } }
        do {
            async let parent = cli.stashParent(index: stash.index)
            async let files = cli.stashFiles(index: stash.index)
            let (p, f) = try await (parent, files)
            guard gen == stashDetailGen else { return }
            stashDetail = StashDetail(
                stash: stash,
                parentSha: p.parentSha,
                parentBranch: stash.parentBranch,
                authorDate: p.authorDate,
                files: f
            )
            stashDetailError = nil
            // Auto-select the first file so the diff pane has content as soon
            // as the detail lands, mirroring CommitDetail's UX. The nested
            // call snapshots its own `stashFileDiffGen`, so a fresher select
            // still wins for the diff pane.
            if let first = f.first {
                await loadStashFileDiff(at: first.path)
            }
        } catch {
            guard gen == stashDetailGen else { return }
            stashDetailError = error.userMessage
        }
    }

    func loadStashFileDiff(at path: String) async {
        guard let stash = selectedStash else { return }
        stashFileDiffGen &+= 1
        let gen = stashFileDiffGen
        selectedStashFile = path
        loadingStashFileDiff = true
        defer { if gen == stashFileDiffGen { loadingStashFileDiff = false } }
        do {
            let raw = try await cli.stashFileDiff(index: stash.index, path: path)
            guard gen == stashFileDiffGen else { return }
            stashFileDiff = DiffParser.parse(raw)
            stashFileDiffEmptyState = .empty
        } catch {
            guard gen == stashFileDiffGen else { return }
            stashFileDiff = []
            stashFileDiffEmptyState = .empty
        }
    }
}
