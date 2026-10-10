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
            stashes = freshStashes
            unmergedLocalBranchRefs = freshUnmerged
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
        let refsSnapshot = refsBySha
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
}
