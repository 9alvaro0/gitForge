import Foundation
import Testing
@testable import gitForge

@Suite("DiffGaps")
struct DiffGapsTests {

    private static func hunks(_ raw: String) -> [DiffHunk] { DiffParser.parse(raw) }

    @Test("Gaps before, between and after the hunks, with old-side offsets")
    func gaps() {
        // 20-line file: line 5 → A (3 context), and line 15 → B, C.
        let hunks = Self.hunks("""
        @@ -2,7 +2,7 @@
         2
         3
         4
        -5
        +A
         6
         7
         8
        @@ -12,7 +12,8 @@
         12
         13
         14
        -15
        +B
        +C
         16
         17
         18
        """)
        let gaps = DiffGaps.gaps(in: hunks, newLineCount: 21)
        #expect(gaps.map(\.beforeHunk) == [0, 1, 2])
        #expect(gaps.map(\.newLines) == [1...1, 9...11, 20...21])
        #expect(gaps.map(\.oldOffset) == [0, 0, -1])
    }

    @Test("No gap where hunks touch the start, each other or the end")
    func noGaps() {
        let hunks = Self.hunks("@@ -1,2 +1,2 @@\n-a\n+b\n c\n")
        #expect(DiffGaps.gaps(in: hunks, newLineCount: 2).isEmpty)
        #expect(DiffGaps.gaps(in: [], newLineCount: 10).isEmpty)
    }

    @Test("A pure deletion hunk sits after its start line")
    func zeroCountSide() {
        // Lines 4-5 deleted from a 10-line file: new side is 8 lines.
        let hunks = Self.hunks("@@ -4,2 +3,0 @@\n-4\n-5\n")
        let gaps = DiffGaps.gaps(in: hunks, newLineCount: 8)
        #expect(gaps.map(\.newLines) == [1...3, 4...8])
        #expect(gaps.map(\.oldOffset) == [0, 2])
    }

    @Test("Gap lines come from the new side with both line numbers")
    func lines() {
        let gap = DiffGap(beforeHunk: 1, newLines: 2...3, oldOffset: 1)
        let lines = gap.lines(from: ["a", "b", "c", "d"])
        #expect(lines.map(\.content) == ["b", "c"])
        #expect(lines.map(\.newLineNumber) == [2, 3])
        #expect(lines.map(\.oldLineNumber) == [3, 4])
        #expect(lines.allSatisfy { $0.kind == .context })
    }

    @Test("splitLines matches the parser's view of a file")
    func split() {
        #expect(DiffGaps.splitLines("a\nb\n") == ["a", "b"])
        #expect(DiffGaps.splitLines("a\nb") == ["a", "b"])
        #expect(DiffGaps.splitLines("a\r\n") == ["a\r"])
        #expect(DiffGaps.splitLines("").isEmpty)
    }

    @Test("fileLines reads a revision and the index")
    func fileLines() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("one", files: ["f.txt": "1\n2\n"])
            try repo.write("1\n2\n3\n", to: "f.txt")
            try repo.git("add", "f.txt")
        }
        defer { repo.remove() }
        #expect(await repo.cli.fileLines(revision: "HEAD", path: "f.txt") == ["1", "2"])
        #expect(await repo.cli.fileLines(revision: "", path: "f.txt") == ["1", "2", "3"])
        #expect(await repo.cli.fileLines(revision: "HEAD", path: "missing.txt") == nil)
    }
}
