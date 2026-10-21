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
    /// Fired when the last row appears, so the host can page in more.
    var onLastRowAppear: ((Commit) -> Void)? = nil
    @ViewBuilder let row: (_ index: Int, _ commit: Commit) -> Row

    var body: some View {
        let commits = commits
        ForEach(commits.indices.lazy.map { CommitRowRef(index: $0, sha: commits[$0].sha) }, id: \.sha) { ref in
            row(ref.index, commits[ref.index])
                // Only the last row pages in more: firing for every row
                // spawned a Task per row scrolled past.
                .onAppear {
                    if ref.index == commits.count - 1 { onLastRowAppear?(commits[ref.index]) }
                }
        }
    }
}

/// A row's position in the log, for its graph layout, and its sha, for its identity.
nonisolated struct CommitRowRef: Sendable {
    let index: Int
    let sha: String
}
