import Foundation
import Testing
@testable import gitForge

/// Where "Blame this line" and the row menus' "Blame" go, and how the blame
/// view cuts the file for the highlighter.
@Suite("File inspector requests")
struct FileInspectorRequestTests {
    private static let sha = String(repeating: "a", count: 40)

    private static func line(_ kind: DiffLine.Kind, old: Int?, new: Int?) -> DiffLine {
        DiffLine(id: 0, kind: kind, content: "x", oldLineNumber: old, newLineNumber: new)
    }

    @Test("In a commit's diff, kept and added lines blame the commit; removed lines its parent, under the old name")
    func commitDiff() {
        let added = FileInspectorRequest.blame(line: Self.line(.added, old: nil, new: 12), commit: Self.sha,
                                               path: "new.swift", previousPath: "old.swift")
        #expect(added?.tab == .blame)
        #expect(added?.path == "new.swift")
        #expect(added?.revision == Self.sha)
        #expect(added?.line == 12)

        let context = FileInspectorRequest.blame(line: Self.line(.context, old: 3, new: 4), commit: Self.sha,
                                                 path: "new.swift", previousPath: nil)
        #expect(context?.line == 4 && context?.revision == Self.sha)

        let removed = FileInspectorRequest.blame(line: Self.line(.removed, old: 9, new: nil), commit: Self.sha,
                                                 path: "new.swift", previousPath: "old.swift")
        #expect(removed?.path == "old.swift")
        #expect(removed?.revision == "\(Self.sha)^")
        #expect(removed?.line == 9)

        #expect(FileInspectorRequest.blame(line: Self.line(.noNewline, old: nil, new: nil), commit: Self.sha,
                                           path: "a", previousPath: nil) == nil)
    }

    @Test("In the working copy's diff, new lines blame the working tree; removed lines HEAD")
    func workingCopyDiff() {
        let added = FileInspectorRequest.blame(line: Self.line(.added, old: nil, new: 5), workingPath: "b.txt",
                                               originalPath: "a.txt")
        #expect(added?.path == "b.txt")
        #expect(added?.revision == nil)
        #expect(added?.line == 5)

        let removed = FileInspectorRequest.blame(line: Self.line(.removed, old: 7, new: nil), workingPath: "b.txt",
                                                 originalPath: "a.txt")
        #expect(removed?.path == "a.txt")
        #expect(removed?.revision == "HEAD")
        #expect(removed?.line == 7)
    }

    @Test("Each request is new, so asking again for the same file reopens the sheet")
    func freshIdentity() {
        #expect(FileInspectorRequest(path: "a") != FileInspectorRequest(path: "a"))
        #expect(FileInspectorRequest(path: "a").tab == .history)
    }

    @Test("The file is cut into chunks of context lines keyed by row")
    func highlightChunks() {
        let lines = (1...450).map { "line \($0)" }

        let chunks = BlameHighlight.chunks(of: lines, size: 200)

        #expect(chunks.map(\.lines.count) == [200, 200, 50])
        #expect(chunks.map(\.id) == [0, 1, 2])
        #expect(chunks[1].lines.first?.id == 200)
        #expect(chunks[1].lines.first?.content == "line 201")
        #expect(chunks[2].lines.last?.id == 449)
        #expect(chunks.flatMap(\.lines).allSatisfy { $0.kind == .context })
        #expect(BlameHighlight.chunks(of: []).isEmpty)
    }
}
