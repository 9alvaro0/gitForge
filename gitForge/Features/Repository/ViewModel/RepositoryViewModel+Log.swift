import Foundation
import os

extension RepositoryViewModel {
    /// Refs the graph walks. **HEAD goes first** so its tip anchors the top of
    /// the topo-ordered log (matches GitKraken's "current branch on top"
    /// behaviour). Then we add **only local branches NOT merged into HEAD** —
    /// merged branches' commits are reached via HEAD's merge ancestry, so
    /// passing them as separate tips just opens redundant lanes that bloat
    /// the column count. Plus tags (labels on already-walked commits, no
    /// extra lanes) and stashes (their own dashed lanes).
    func graphScope() -> [String] {
        var refs: [String] = ["HEAD"]
        refs.append(contentsOf: unmergedLocalBranchRefs)
        refs.append("--tags")
        refs.append(contentsOf: stashes.map(\.sha))
        return refs
    }

    func loadInitial() async {
        guard commits.isEmpty, !isLoadingInitial else { return }
        isLoadingInitial = true
        defer {
            isLoadingInitial = false
            hasLoadedLogForCurrentScope = true
        }
        do {
            // Stashes and unmerged-branch refs are both part of the graph scope.
            // Pull them inline if loadRefs hasn't populated them yet — otherwise
            // the first paint walks an incomplete scope (missing unmerged
            // branches → no separate lanes for `feature/foo` work; missing
            // stashes → no dashed dots) and we'd need a full reload to fix it.
            if stashes.isEmpty {
                stashes = (try? await cli.stashes()) ?? []
            }
            if unmergedLocalBranchRefs.isEmpty {
                unmergedLocalBranchRefs = (try? await cli.unmergedLocalBranches()) ?? []
            }
            let page = try await cli.log(limit: Self.pageSize, skip: 0, refs: graphScope())
            commits = page
            loadedRawCount = page.count
            dropStashInternals()
            hasMore = page.count == Self.pageSize
            selectedCommitId = commits.first?.id
            recomputeGraph()
        } catch {
            Self.logger.error("Failed to load log: \(error.localizedDescription, privacy: .public)")
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Refetches the first page using the current `graphScope()` and swaps it
    /// into `commits` atomically — without first emptying the array. Keeps the
    /// old rows on screen during the fetch so the History view doesn't flash
    /// empty (and the ScrollView keeps its offset) when HEAD moves: branch
    /// checkout, pull, commit, merge, watcher-detected external change…
    ///
    /// The user's selection is preserved when the previously-selected commit
    /// is still in the new page; otherwise it falls back to the new first
    /// commit (matching `loadInitial`'s default).
    func reloadLog() async {
        let previousSelection = selectedCommitId
        do {
            stashes = (try? await cli.stashes()) ?? []
            unmergedLocalBranchRefs = (try? await cli.unmergedLocalBranches()) ?? []
            let page = try await cli.log(limit: Self.pageSize, skip: 0, refs: graphScope())
            commits = page
            loadedRawCount = page.count
            dropStashInternals()
            hasMore = page.count == Self.pageSize
            if let prev = previousSelection,
               !commits.contains(where: { $0.id == prev }) {
                selectedCommitId = commits.first?.id
            }
            recomputeGraph()
            hasLoadedLogForCurrentScope = true
        } catch {
            Self.logger.error("Failed to reload log: \(error.localizedDescription, privacy: .public)")
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func loadMoreIfNeeded(currentItem: Commit) async {
        guard hasMore, !isLoadingMore else { return }
        guard let last = commits.last, last.id == currentItem.id else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let next = try await cli.log(limit: Self.pageSize, skip: loadedRawCount, refs: graphScope())
            loadedRawCount += next.count
            commits.append(contentsOf: next)
            dropStashInternals()
            hasMore = next.count == Self.pageSize
            recomputeGraph()
        } catch {
            Self.logger.error("Failed to load more: \(error.localizedDescription, privacy: .public)")
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Scrolls the log to the given SHA, paginating in if it isn't loaded yet.
    /// Stops at `maxRevealPages` so a stray ref doesn't load the entire history.
    func revealCommit(sha: String) async {
        if commits.contains(where: { $0.sha == sha }) {
            scrollTargetSha = sha
            return
        }
        guard hasMore else { return }
        isRevealingCommit = true
        defer { isRevealingCommit = false }
        var pagesLoaded = 0
        while hasMore && pagesLoaded < Self.maxRevealPages {
            do {
                let next = try await cli.log(limit: Self.pageSize, skip: loadedRawCount, refs: graphScope())
                loadedRawCount += next.count
                commits.append(contentsOf: next)
                dropStashInternals()
                hasMore = next.count == Self.pageSize
                recomputeGraph()
                pagesLoaded += 1
                if commits.contains(where: { $0.sha == sha }) {
                    scrollTargetSha = sha
                    return
                }
            } catch {
                Self.logger.error("Reveal pagination failed: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
    }

    func recomputeGraph() {
        let stashShas = Set(stashes.map(\.sha))
        let result = GraphLayoutEngine.layouts(for: commits, refsBySha: refsBySha, stashShas: stashShas)
        graphLayouts = result.rows
        graphMaxLanes = max(1, result.maxLanes)
    }

    /// Removes stash *internal* commits — `parent[1]` (index tree) and
    /// `parent[2]` (untracked tree) of each stash. Those are git plumbing the
    /// user never asked for; surfacing them as separate rows ("index on main:
    /// …", "untracked files on main: …") clutters the log. `git log` walks
    /// them automatically when we pass the stash sha as a ref, so we filter
    /// them here. Does not touch the stash commit itself — that one stays
    /// visible as the dashed dot in the graph. Matches GitKraken's behaviour.
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

    /// Wipes log state so the next `loadInitial` reads a fresh head. Used by
    /// commit / pull / branch ops that change HEAD.
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
