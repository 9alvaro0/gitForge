import SwiftUI

/// The History table's commit rows, one per commit, identified by its sha.
///
/// The sha must be the `ForEach`'s own identity. An index-identified
/// `ForEach` whose rows carried an inner `.id(sha)` went stale inside the
/// lazy stack: when a reload moved a commit to another index (a new stash on
/// top, a dropped one), its row kept the view it had and never re-ran its
/// body, so it went on drawing the graph of its old position until the table
/// was rebuilt. The sha identity also gives `ScrollViewReader.scrollTo(sha)`
/// its targets and keeps a row's hover and drop state with its commit.
///
/// The rows come from a lazy view over `commits`, so a re-render neither
/// copies the log nor builds an array of rows.
struct CommitRowList<Row: View>: View {
    let commits: [Commit]
    /// The host's revision of `commits` (`HistoryStore.logRevision`): it moves
    /// each time the log is published, even with the same rows.
    var revision: UInt64 = 0
    /// Fired with the last commit when the end of the list is on screen: when
    /// it scrolls into view, and when a log published while it is in view ends
    /// there too, so the host can page in more.
    var onLastRowAppear: ((Commit) -> Void)? = nil
    @ViewBuilder let row: (_ index: Int, _ commit: Commit) -> Row

    var body: some View {
        let commits = commits
        ForEach(commits.indices.lazy.map { CommitRowRef(index: $0, sha: commits[$0].sha) }, id: \.sha) { ref in
            row(ref.index, commits[ref.index])
        }
        // A marker after the rows pages in more, not the last row: a reload that
        // drops pages while the end is on screen leaves a last row that was visible
        // all along, so nothing about it changes. The marker's identity is the
        // published log's (length, last sha and revision), so each published log
        // gets a new marker, which fires if it lands on screen. It comes from a
        // one-element `ForEach`: the lazy stack doesn't take an `.id` change on a
        // plain child as a new view. It fires on screen visibility, not `onAppear`:
        // the lazy stack builds views ahead of the scroll in idle time, and paging
        // from there loaded pages nobody scrolled to. Only the marker fires, so
        // scrolling spawns one Task per page, not per row.
        if let last = commits.last, let onLastRowAppear {
            ForEach([CommitRowListEnd(count: commits.count, lastSha: last.sha, revision: revision)], id: \.self) { _ in
                // 1 pt high: an empty frame never counts as visible. Any sliver
                // counts: with many lanes the table is wider than the window,
                // and only part of the marker's width is on screen.
                Color.clear
                    .frame(height: 1)
                    .onScrollVisibilityChange(threshold: 0.01) { visible in
                        if visible { onLastRowAppear(last) }
                    }
            }
        }
    }
}

/// A row's position in the log, for its graph layout, and its sha, for its identity.
nonisolated struct CommitRowRef: Sendable {
    let index: Int
    let sha: String
}

/// Identity of the marker after the last row: it changes whenever a log is
/// published, wherever it ends.
nonisolated struct CommitRowListEnd: Hashable, Sendable {
    let count: Int
    let lastSha: String
    let revision: UInt64
}
