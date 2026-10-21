import Foundation
import Testing
@testable import gitForge

@Suite("Thread placement")
struct ThreadPlacementTests {
    static let patch = """
    @@ -10,3 +10,4 @@
     let a = 1
    -let b = 2
    +let b = 3
    +let c = 4
    """
    static let file = PullRequestFileChange(path: "Sources/Retry.swift", oldPath: "Sources/Old.swift", status: .renamed,
                                            additions: 2, deletions: 1, patch: patch)

    static func thread(_ id: String, path: String = "Sources/Retry.swift", ref: DiffLineRef?, outdated: Bool = false,
                       resolved: Bool = false) -> ReviewThread {
        ReviewThread(id: id, path: path, oldPath: nil, ref: ref, originalLine: ref?.line, isResolved: resolved, isOutdated: outdated,
                     resolvedBy: nil, comments: [], canReply: true, canResolve: true, canUnresolve: false, replyToCommentId: nil)
    }

    @Test("Threads land under their line on either side, context lines included")
    func inline() {
        let placed = ThreadPlacement.place([
            Self.thread("new", ref: .init(side: .new, line: 12)),
            Self.thread("old", ref: .init(side: .old, line: 11)),
            Self.thread("ctx-left", ref: .init(side: .old, line: 10)),
        ], in: [Self.file])
        #expect(placed.inline["Sources/Retry.swift"]?[.init(side: .new, line: 12)]?.map(\.id) == ["new"])
        #expect(placed.inline["Sources/Retry.swift"]?[.init(side: .old, line: 11)]?.map(\.id) == ["old"])
        #expect(placed.inline["Sources/Retry.swift"]?[.init(side: .old, line: 10)]?.map(\.id) == ["ctx-left"])
    }

    @Test("Outdated, unplaceable and patch-less threads go to the top of their file")
    func fileLevel() {
        let binary = PullRequestFileChange(path: "logo.png", oldPath: nil, status: .modified, additions: 0, deletions: 0, patch: nil)
        let placed = ThreadPlacement.place([
            Self.thread("outdated", ref: .init(side: .new, line: 12), outdated: true),
            Self.thread("gone-line", ref: .init(side: .new, line: 99)),
            Self.thread("binary", path: "logo.png", ref: .init(side: .new, line: 1)),
        ], in: [Self.file, binary])
        #expect(placed.fileLevel["Sources/Retry.swift"]?.map(\.id) == ["outdated", "gone-line"])
        #expect(placed.fileLevel["logo.png"]?.map(\.id) == ["binary"])
    }

    @Test("Old paths of renames match; files not in the list go to Other; counts skip resolved")
    func otherAndCounts() {
        let placed = ThreadPlacement.place([
            Self.thread("renamed", path: "Sources/Old.swift", ref: nil),
            Self.thread("reverted", path: "Sources/Gone.swift", ref: .init(side: .new, line: 3)),
            Self.thread("done", ref: .init(side: .new, line: 12), resolved: true),
        ], in: [Self.file])
        #expect(placed.fileLevel["Sources/Retry.swift"]?.map(\.id) == ["renamed"])
        #expect(placed.other.map(\.id) == ["reverted"])
        #expect(placed.openCount(for: "Sources/Retry.swift") == 1)
        #expect(placed.otherOpenCount == 1)
    }

    @Test("Placing threads again parses each patch once; a new patch is parsed again")
    func parsesEachPatchOnce() {
        let parses = CallCount()
        var index = DiffLineIndex(parse: { parses.add(); return DiffParser.parse($0) })
        let open = [Self.thread("t", ref: .init(side: .new, line: 12))]
        _ = ThreadPlacement.place(open, in: [Self.file], index: &index)
        let resolved = ThreadPlacement.place([Self.thread("t", ref: .init(side: .new, line: 12), resolved: true)],
                                             in: [Self.file], index: &index)
        #expect(parses.value == 1)
        #expect(resolved.inline["Sources/Retry.swift"]?[.init(side: .new, line: 12)]?.map(\.id) == ["t"])

        // New commits took line 12 away.
        let pushed = PullRequestFileChange(path: "Sources/Retry.swift", oldPath: "Sources/Old.swift", status: .renamed,
                                           additions: 1, deletions: 1, patch: "@@ -10,2 +10,2 @@\n let a = 1\n-let b = 2\n+let b = 5")
        let placed = ThreadPlacement.place(open, in: [pushed], index: &index)
        #expect(parses.value == 2)
        #expect(placed.fileLevel["Sources/Retry.swift"]?.map(\.id) == ["t"])
        #expect(placed.inline.isEmpty)
    }

    @Test("Comment targets keep both numbers on context lines and refuse no-newline")
    func targets() {
        let context = DiffLine(id: 0, kind: .context, content: "x", oldLineNumber: 10, newLineNumber: 10)
        let target = CommentTarget.make(path: "a", oldPath: nil, line: context, side: .new)
        #expect(target?.oldLine == 10 && target?.newLine == 10 && target?.ref == .init(side: .new, line: 10))
        let marker = DiffLine(id: 1, kind: .noNewline, content: "", oldLineNumber: nil, newLineNumber: nil)
        #expect(CommentTarget.make(path: "a", oldPath: nil, line: marker, side: .new) == nil)
        #expect(DiffLineRef.commentSide(for: DiffLine(id: 2, kind: .removed, content: "", oldLineNumber: 11, newLineNumber: nil)) == .old)
    }
}
