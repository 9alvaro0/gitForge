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
    /// Fired with the last commit when the end of the list comes into view, so
    /// the host can page in more.
    var onLastRowAppear: ((Commit) -> Void)? = nil
    @ViewBuilder let row: (_ index: Int, _ commit: Commit) -> Row

    var body: some View {
        let commits = commits
        ForEach(commits.indices.lazy.map { CommitRowRef(index: $0, sha: commits[$0].sha) }, id: \.sha) { ref in
            row(ref.index, commits[ref.index])
        }
        // An empty marker after the rows pages in more, not the last row's own
        // `onAppear`: a reload that drops pages while the end is on screen leaves
        // a last row that was visible all along and keeps its identity, so it
        // never appears again. The marker's identity is the log's length and last
        // sha, so a log that ends elsewhere gets a new marker, which appears. It
        // comes from a one-element `ForEach`: the lazy stack doesn't run
        // `onAppear` again for an `.id` change on a plain child. Only the marker
        // fires, not every row, so scrolling spawns one Task per page, not per row.
        if let last = commits.last, let onLastRowAppear {
            ForEach([CommitRowListEnd(count: commits.count, lastSha: last.sha)], id: \.self) { _ in
                Color.clear
                    .frame(height: 0)
                    .onAppear { onLastRowAppear(last) }
            }
        }
    }
}

/// A row's position in the log, for its graph layout, and its sha, for its identity.
nonisolated struct CommitRowRef: Sendable {
    let index: Int
    let sha: String
}

/// Identity of the marker after the last row: it changes whenever the log ends elsewhere.
nonisolated struct CommitRowListEnd: Hashable, Sendable {
    let count: Int
    let lastSha: String
}
