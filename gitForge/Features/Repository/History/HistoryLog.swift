import Foundation

/// A loaded log as the graph lays it out: its rows, the pages they came in
/// and the stashes they were fetched with. `HistoryStore` builds the next one
/// off to the side and publishes it together with its graph.
nonisolated struct HistoryLog: Sendable, Equatable {
    var commits: [Commit] = []
    /// Raw commits `git log` produced for these pages, before stash internals
    /// were dropped: the next page's `--skip`, so pages can't overlap.
    var rawCount = 0
    /// Row index one past the end of each page, strictly ascending
    /// (`GraphInput.pageEnds`).
    var pageEnds: [Int] = []
    /// The log's stash commits: drawn as stashes, their internal commits
    /// dropped. Fixed by the fetches that built the log, not by the live
    /// stash list, so a stash dropped since then stays a stash until the log
    /// is replaced.
    var stashShas: Set<String> = []

    /// A log that starts over with `page`, fetched with `stashShas` in its scope.
    static func firstPage(_ page: [Commit], stashShas: Set<String>) -> HistoryLog {
        var log = HistoryLog(commits: page, rawCount: page.count, pageEnds: [], stashShas: stashShas)
        log.dropStashInternals(from: 0)
        log.pageEnds = [log.commits.count]
        return log
    }

    /// A log of `commits`, fetched in one walk with `stashShas` in its scope, split
    /// into pages of `pageSize` raw commits as if they had loaded one by one
    /// (`firstPage`, then `appending` each next one): the same rows and page ends,
    /// so its first page reserves the same columns (§3.9).
    static func paged(_ commits: [Commit], pageSize: Int, stashShas: Set<String>) -> HistoryLog {
        let size = max(pageSize, 1)
        var log = firstPage(Array(commits.prefix(size)), stashShas: stashShas)
        var start = size
        while start < commits.count {
            let end = min(start + size, commits.count)
            log = log.appending(Array(commits[start..<end]), scopeStashShas: stashShas)
            start = end
        }
        return log
    }

    /// This log with `page` appended. The page was fetched with the scope's
    /// stashes at the time, `scopeStashShas`. Only the ones that are rows of
    /// the new page join the log's stashes, and internals go from the new
    /// rows only: no row already drawn changes kind or position, so the
    /// earlier pages stay exactly as they were (§3.9). A stash in the log
    /// stays one even if the live list has dropped it since.
    ///
    /// A commit already loaded is not added again: `--skip` pagination
    /// repeats a boundary commit when the log grows between two pages, and
    /// rows are identified by sha. `rawCount` still counts every raw commit,
    /// so the next `--skip` stays right.
    func appending(_ page: [Commit], scopeStashShas: Set<String>) -> HistoryLog {
        var log = self
        let start = log.commits.count
        log.rawCount += page.count
        var seen = Set(log.commits.map(\.sha))
        let fresh = page.filter { seen.insert($0.sha).inserted }
        log.commits.append(contentsOf: fresh)
        let newRows = Set(fresh.map(\.sha))
        log.stashShas.formUnion(scopeStashShas.filter { newRows.contains($0) })
        log.dropStashInternals(from: start)
        // A page that adds no rows (all stash internals, or none at all) adds
        // no page end, so the list stays strictly ascending.
        if log.commits.count > (log.pageEnds.last ?? 0) {
            log.pageEnds.append(log.commits.count)
        }
        return log
    }

    /// Removes stash *internal* commits — `parent[1]` (index tree) and
    /// `parent[2]` (untracked tree) of each of the log's stashes — from the
    /// rows at `start` and below. They are git plumbing the user never asked
    /// for; the stash itself stays, drawn as a dashed square. A stash on an
    /// earlier page still loses the internals that land on a later one.
    private mutating func dropStashInternals(from start: Int) {
        guard !stashShas.isEmpty else { return }
        var internals: Set<String> = []
        for commit in commits where stashShas.contains(commit.sha) {
            // parent[0] is the real HEAD when the stash was taken — keep it.
            for (index, parent) in commit.parentShas.enumerated() where index >= 1 {
                internals.insert(parent)
            }
        }
        guard !internals.isEmpty else { return }
        let start = min(max(start, 0), commits.count)
        guard commits[start...].contains(where: { internals.contains($0.sha) }) else { return }
        commits[start...].removeAll { internals.contains($0.sha) }
    }
}
