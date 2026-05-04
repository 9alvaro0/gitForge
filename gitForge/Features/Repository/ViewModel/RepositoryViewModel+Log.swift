import Foundation
import os

extension RepositoryViewModel {
    func loadInitial() async {
        guard commits.isEmpty, !isLoadingInitial else { return }
        isLoadingInitial = true
        defer { isLoadingInitial = false }
        do {
            let page = try await cli.log(limit: Self.pageSize, skip: 0)
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
            let next = try await cli.log(limit: Self.pageSize, skip: commits.count)
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
                let next = try await cli.log(limit: Self.pageSize, skip: commits.count)
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
        let result = GraphLayoutEngine.layouts(for: commits)
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
