import Foundation
import os

extension RepositoryViewModel {
    /// Refs the graph walks. Local branches + tags + HEAD + every stash, so the
    /// log paginates through the full history that's reachable locally (without
    /// `--tags` the user could scroll past the last release-merge and the log
    /// would just stop). Remote-tracking refs (`--remotes`) are intentionally
    /// out — they typically duplicate local branches and would re-introduce the
    /// column explosion we removed when we dropped `--all`. Tags are mostly
    /// labels on already-walked commits, so they extend reach without
    /// allocating extra lanes.
    func graphScope() -> [String] {
        var refs: [String] = ["--branches", "--tags", "HEAD"]
        refs.append(contentsOf: stashes.map(\.sha))
        return refs
    }

    func loadInitial() async {
        guard commits.isEmpty, !isLoadingInitial else { return }
        isLoadingInitial = true
        defer { isLoadingInitial = false }
        do {
            // Stashes are part of the graph scope. Pull them inline if loadRefs
            // hasn't populated them yet — otherwise the first paint misses any
            // stash dots and we'd need a full reload to surface them.
            if stashes.isEmpty {
                stashes = (try? await cli.stashes()) ?? []
            }
            let page = try await cli.log(limit: Self.pageSize, skip: 0, refs: graphScope())
            commits = page
            hasMore = page.count == Self.pageSize
            selectedCommitId = page.first?.id
            recomputeGraph()
        } catch {
            Self.logger.error("Failed to load log: \(error.localizedDescription, privacy: .public)")
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func loadMoreIfNeeded(currentItem: Commit) async {
        guard hasMore, !isLoadingMore else { return }
        guard let last = commits.last, last.id == currentItem.id else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let next = try await cli.log(limit: Self.pageSize, skip: commits.count, refs: graphScope())
            commits.append(contentsOf: next)
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
                let next = try await cli.log(limit: Self.pageSize, skip: commits.count, refs: graphScope())
                commits.append(contentsOf: next)
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

    /// Wipes log state so the next `loadInitial` reads a fresh head. Used by
    /// commit / pull / branch ops that change HEAD.
    func resetLog() {
        commits = []
        graphLayouts = []
        graphMaxLanes = 1
        hasMore = true
        selectedCommitId = nil
    }
}
