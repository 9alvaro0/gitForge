import Foundation

/// One comment in a review thread.
nonisolated struct ReviewComment: Sendable, Equatable, Identifiable {
    let id: String
    let authorLogin: String?
    let authorAvatarURL: URL?
    let body: String
    let createdAt: Date?
}

/// A conversation on a line of a PR/MR (a GitHub review thread, a GitLab
/// diff discussion), in host-neutral terms.
nonisolated struct ReviewThread: Sendable, Equatable, Identifiable {
    let id: String
    let path: String
    /// The path before a rename, when the host gives one.
    let oldPath: String?
    /// Where the thread sits in the current diff; `nil` when the host
    /// doesn't place it there any more.
    let ref: DiffLineRef?
    /// The line it was left on, for threads the diff moved past.
    let originalLine: Int?
    var isResolved: Bool
    /// Left on code the latest commits changed.
    let isOutdated: Bool
    var resolvedBy: String?
    var comments: [ReviewComment]
    let canReply: Bool
    var canResolve: Bool
    var canUnresolve: Bool
    /// GitHub answers a thread through its first comment.
    let replyToCommentId: String?
}

/// The line a new comment goes on.
nonisolated struct CommentTarget: Hashable, Sendable {
    let path: String
    let oldPath: String?
    let side: DiffSide
    /// Both numbers on a context line (GitLab wants both there); one on an
    /// added or removed line.
    let oldLine: Int?
    let newLine: Int?
    var ref: DiffLineRef

    /// `nil` on "No newline at end of file", or when `line` has no number
    /// on `side`.
    static func make(path: String, oldPath: String?, line: DiffLine, side: DiffSide) -> CommentTarget? {
        guard line.kind != .noNewline,
              let number = side == .old ? line.oldLineNumber : line.newLineNumber else { return nil }
        return CommentTarget(path: path, oldPath: oldPath, side: side,
                             oldLine: line.oldLineNumber, newLine: line.newLineNumber,
                             ref: DiffLineRef(side: side, line: number))
    }
}
