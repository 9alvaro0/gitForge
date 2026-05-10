import Foundation

extension RepositoryViewModel {
    /// Refs the graph walks. HEAD goes first so its tip anchors the top of
    /// the topo-ordered log (matches GitKraken). Local branches not merged
    /// into HEAD become their own lanes; merged ones ride along via HEAD's
    /// merge ancestry — passing them as separate tips would just bloat the
    /// column count. Tags are labels on already-walked commits; stashes
    /// surface as their own dashed lanes.
    func graphScope() -> [String] {
        var refs: [String] = ["HEAD"]
        refs.append(contentsOf: unmergedLocalBranchRefs)
        refs.append("--tags")
        refs.append(contentsOf: stashes.map(\.sha))
        return refs
    }

    func loadInitial() async {
        guard commits.isEmpty, !isLoadingInitial else { return }
        logGen &+= 1
        let gen = logGen
        isLoadingInitial = true
        loadError = nil
        defer {
            if gen == logGen {
                isLoadingInitial = false
                hasLoadedLogForCurrentScope = true
            }
        }
        let pageSize = AppTheme.persistedCommitPageSize()
        do {
            // Stashes + unmerged-branch refs feed graphScope(); without them
            // the first paint walks an incomplete scope. Run both in
            // parallel when neither has been seeded by an earlier loadRefs().
            if stashes.isEmpty || unmergedLocalBranchRefs.isEmpty {
                async let stashTask = cli.stashes()
                async let unmergedTask = cli.unmergedLocalBranches()
                if stashes.isEmpty {
                    stashes = (try? await stashTask) ?? []
                }
                if unmergedLocalBranchRefs.isEmpty {
                    unmergedLocalBranchRefs = (try? await unmergedTask) ?? []
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
            recomputeGraph()
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
        let pageSize = AppTheme.persistedCommitPageSize()
        do {
            async let stashTask = cli.stashes()
            async let unmergedTask = cli.unmergedLocalBranches()
            stashes = (try? await stashTask) ?? []
            unmergedLocalBranchRefs = (try? await unmergedTask) ?? []
            guard gen == logGen else { return }
            let page = try await cli.log(limit: pageSize, skip: 0, refs: graphScope())
            guard gen == logGen else { return }
            commits = page
            loadedRawCount = page.count
            dropStashInternals()
            hasMore = page.count == pageSize
            if let prev = previousSelection, commitsById[prev] == nil {
                selectedCommitId = commits.first?.id
            }
            recomputeGraph()
            hasLoadedLogForCurrentScope = true
        } catch {
            guard gen == logGen else { return }
            loadError = error.userMessage
        }
    }

    func loadMoreIfNeeded(currentItem: Commit) async {
        guard hasMore, !isLoadingMore else { return }
        guard let last = commits.last, last.id == currentItem.id else { return }
        logGen &+= 1
        let gen = logGen
        isLoadingMore = true
        loadError = nil
        defer { if gen == logGen { isLoadingMore = false } }
        let pageSize = AppTheme.persistedCommitPageSize()
        do {
            _ = try await paginateNextPage(gen: gen, pageSize: pageSize)
        } catch {
            guard gen == logGen else { return }
            loadError = error.userMessage
        }
    }

    /// Scrolls the log to `sha`, paginating in if it isn't loaded yet. Caps
    /// at `maxRevealPages` so a stray ref can't quietly walk the entire
    /// history.
    func revealCommit(sha: String) async {
        if commitsById[sha] != nil {
            scrollTargetSha = sha
            return
        }
        guard hasMore else { return }
        logGen &+= 1
        let gen = logGen
        isRevealingCommit = true
        defer { if gen == logGen { isRevealingCommit = false } }
        let pageSize = AppTheme.persistedCommitPageSize()
        var pagesLoaded = 0
        while hasMore && pagesLoaded < Self.maxRevealPages {
            do {
                guard try await paginateNextPage(gen: gen, pageSize: pageSize) != nil else { return }
                pagesLoaded += 1
                if commitsById[sha] != nil {
                    scrollTargetSha = sha
                    return
                }
            } catch {
                guard gen == logGen else { return }
                return
            }
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
        recomputeGraph()
        return next
    }

    func recomputeGraph() {
        let stashShas = Set(stashes.map(\.sha))
        let result = GraphLayoutEngine.layouts(for: commits, refsBySha: refsBySha, stashShas: stashShas)
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

    /// Wipes log state so the next `loadInitial` reads a fresh head. Used
    /// by commit / pull / branch ops that change HEAD.
    func resetLog() {
        commits = []
        loadedRawCount = 0
        graphLayouts = []
        graphMaxLanes = 1
        hasMore = true
        selectedCommitId = nil
        hasLoadedLogForCurrentScope = false
    }
}
