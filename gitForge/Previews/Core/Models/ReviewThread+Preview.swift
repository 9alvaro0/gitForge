import Foundation

extension ReviewThread {
    /// Two comments under line 2 of `Sources/Foo.swift` (the preview patch).
    static let previewOpen = ReviewThread(
        id: "preview-open", path: "Sources/Foo.swift", oldPath: nil, ref: DiffLineRef(side: .new, line: 2),
        originalLine: 2, isResolved: false, isOutdated: false, resolvedBy: nil,
        comments: [
            ReviewComment(id: "1", authorLogin: "marta", authorAvatarURL: nil,
                          body: "Should this retry **forever**? A cap of 3 seems safer.",
                          createdAt: Date(timeIntervalSinceNow: -7_200)),
            ReviewComment(id: "2", authorLogin: "octocat", authorAvatarURL: nil,
                          body: "Good catch, capped at `3` now.", createdAt: Date(timeIntervalSinceNow: -3_600)),
        ],
        canReply: true, canResolve: true, canUnresolve: false, replyToCommentId: "1")

    static let previewResolved = ReviewThread(
        id: "preview-resolved", path: "Sources/Foo.swift", oldPath: nil, ref: DiffLineRef(side: .old, line: 2),
        originalLine: 2, isResolved: true, isOutdated: false, resolvedBy: "marta",
        comments: [ReviewComment(id: "3", authorLogin: "marta", authorAvatarURL: nil, body: "Why remove this?",
                                 createdAt: Date(timeIntervalSinceNow: -86_400))],
        canReply: true, canResolve: false, canUnresolve: true, replyToCommentId: "3")

    static let previewOutdated = ReviewThread(
        id: "preview-outdated", path: "Sources/Foo.swift", oldPath: nil, ref: nil, originalLine: 9,
        isResolved: false, isOutdated: true, resolvedBy: nil,
        comments: [ReviewComment(id: "4", authorLogin: "marta", authorAvatarURL: nil, body: "Typo in the log message.",
                                 createdAt: Date(timeIntervalSinceNow: -172_800))],
        canReply: true, canResolve: true, canUnresolve: false, replyToCommentId: "4")

    /// On a file the PR no longer changes.
    static let previewElsewhere = ReviewThread(
        id: "preview-elsewhere", path: "Sources/Removed.swift", oldPath: nil, ref: DiffLineRef(side: .new, line: 4),
        originalLine: 4, isResolved: false, isOutdated: false, resolvedBy: nil,
        comments: [ReviewComment(id: "5", authorLogin: "octocat", authorAvatarURL: nil, body: "Is this still needed?",
                                 createdAt: Date(timeIntervalSinceNow: -600))],
        canReply: true, canResolve: true, canUnresolve: false, replyToCommentId: "5")
}
