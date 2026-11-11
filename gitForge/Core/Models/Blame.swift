import Foundation

/// A commit as `git blame` describes it: who wrote the lines and when, and
/// the commit's subject.
nonisolated struct BlameCommit: Sendable, Equatable, Identifiable, Hashable {
    let sha: String
    let authorName: String
    let authorEmail: String
    let authorDate: Date
    let summary: String
    /// The commit is where blame stopped looking (a root commit): its lines
    /// may be older than it, and there is nothing before it to blame.
    let isBoundary: Bool

    var id: String { sha }
    var shortSha: String { String(sha.prefix(7)) }

    /// Lines in the working tree or the index that no commit has yet: git
    /// blames them on the all-zero SHA.
    var isUncommitted: Bool { Self.isUncommitted(sha) }

    static func isUncommitted(_ sha: String) -> Bool {
        !sha.isEmpty && sha.allSatisfy { $0 == "0" }
    }
}

/// Where a commit's version of a file came from: the parent blame looked
/// in and the file's name there (git's `previous` line).
nonisolated struct BlameOrigin: Sendable, Equatable, Hashable {
    let sha: String
    let path: String
}

/// A run of lines of the blamed file that one commit last changed.
nonisolated struct BlameRange: Sendable, Equatable, Hashable {
    let sha: String
    /// The first line's number in the commit's version of `path`.
    let sourceLine: Int
    /// The first line's number in the blamed file (1-based).
    let finalLine: Int
    let count: Int
    /// The file's name in that commit: another file's for lines `-M -C`
    /// found moved or copied from it.
    let path: String
    /// Where "Blame before this commit" goes; `nil` for a boundary commit.
    let previous: BlameOrigin?

    /// Whether `line` (in the blamed file) is one of this range's.
    func contains(_ line: Int) -> Bool {
        line >= finalLine && line < finalLine + count
    }

    /// `line`'s number in the commit's version of the file.
    func sourceLine(for line: Int) -> Int {
        sourceLine + (line - finalLine)
    }
}
