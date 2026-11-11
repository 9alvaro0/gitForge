import Foundation
import Testing
@testable import gitForge

/// `BlameParser` over hand-written output, chunked in awkward places, and
/// `BlameLineMapping` over `-U0` hunks.
@Suite("Blame parser")
struct BlameParserTests {
    private static let a = String(repeating: "a", count: 40)
    private static let b = String(repeating: "b", count: 40)
    private static let zero = String(repeating: "0", count: 40)

    /// Two commits, `a` over lines 1–2 and 4, `b` over line 3; `a` is a root
    /// commit (boundary), `b`'s parent is `a`.
    private static let incremental = """
        \(b) 3 3 1
        author Bea
        author-mail <bea@example.com>
        author-time 1700000000
        author-tz +0100
        committer Bea
        committer-mail <bea@example.com>
        committer-time 1700000000
        committer-tz +0100
        summary Fix the third line
        previous \(a) old name.txt
        filename new name.txt
        \(a) 1 1 2
        author Al
        author-mail <al@example.com>
        author-time 1600000000
        author-tz +0000
        committer Al
        committer-mail <al@example.com>
        committer-time 1600000000
        committer-tz +0000
        summary First
        boundary
        filename old name.txt
        \(a) 4 4 1
        boundary
        filename old name.txt

        """

    @Test("Incremental records: one commit each the first time, every range with its path and parent")
    func incremental() throws {
        let batch = BlameParser.parse(Self.incremental)

        #expect(batch.commits.map(\.sha) == [Self.b, Self.a])
        let bea = batch.commits[0]
        #expect(bea.authorName == "Bea")
        #expect(bea.authorEmail == "bea@example.com")
        #expect(bea.authorDate == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(bea.summary == "Fix the third line")
        #expect(!bea.isBoundary && !bea.isUncommitted)
        #expect(batch.commits[1].isBoundary)

        #expect(batch.ranges == [
            BlameRange(sha: Self.b, sourceLine: 3, finalLine: 3, count: 1, path: "new name.txt",
                       previous: BlameOrigin(sha: Self.a, path: "old name.txt")),
            BlameRange(sha: Self.a, sourceLine: 1, finalLine: 1, count: 2, path: "old name.txt", previous: nil),
            BlameRange(sha: Self.a, sourceLine: 4, finalLine: 4, count: 1, path: "old name.txt", previous: nil),
        ])
        #expect(batch.contents.isEmpty)
    }

    @Test("Fed in chunks split mid-line and mid-character, it reads the same")
    func chunked() {
        let text = Self.incremental.replacingOccurrences(of: "Fix the third line", with: "Arreglo de la línea ñ")
        let data = Data(text.utf8)
        var parser = BlameParser()
        var commits: [BlameCommit] = []
        var ranges: [BlameRange] = []
        var offset = 0
        // 7-byte chunks split lines, and "í" / "ñ" (two bytes each) somewhere.
        while offset < data.count {
            let end = min(offset + 7, data.count)
            let batch = parser.feed(data.subdata(in: offset..<end))
            commits += batch.commits
            ranges += batch.ranges
            offset = end
        }
        let tail = parser.finish()
        commits += tail.commits
        ranges += tail.ranges

        let whole = BlameParser.parse(text)
        #expect(commits == whole.commits)
        #expect(ranges == whole.ranges)
        #expect(commits.first?.summary == "Arreglo de la línea ñ")
    }

    @Test("Porcelain: contents by line, and repeated records keep their commit's path and parent")
    func porcelain() {
        let text = """
            \(Self.b) 1 1 2
            author Bea
            author-mail <bea@example.com>
            author-time 1700000000
            author-tz +0000
            summary Two lines
            previous \(Self.a) f.txt
            filename f.txt
            \tfirst
            \(Self.b) 2 2
            \tsecond\twith tab
            \(Self.a) 1 3 1
            author Al
            author-mail <al@example.com>
            author-time 1600000000
            author-tz +0000
            summary Root
            boundary
            filename f.txt
            \t
            """

        let batch = BlameParser.parse(text)

        #expect(batch.commits.map(\.sha) == [Self.b, Self.a])
        #expect(batch.ranges.map(\.finalLine) == [1, 2, 3])
        #expect(batch.ranges.map(\.count) == [2, 1, 1])
        #expect(batch.ranges[1].path == "f.txt")
        #expect(batch.ranges[1].previous == BlameOrigin(sha: Self.a, path: "f.txt"))
        #expect(batch.ranges[2].previous == nil)
        #expect(batch.contents == [1: "first", 2: "second\twith tab", 3: ""])
    }

    @Test("Uncommitted lines are blamed on the all-zero SHA")
    func uncommitted() {
        let text = """
            \(Self.zero) 2 2 1
            author Not Committed Yet
            author-mail <not.committed.yet>
            author-time 1700000000
            author-tz +0000
            summary Version of f.txt from f.txt
            previous \(Self.a) f.txt
            filename f.txt

            """

        let batch = BlameParser.parse(text)

        #expect(batch.commits.first?.isUncommitted == true)
        #expect(batch.commits.first?.authorEmail == "not.committed.yet")
        #expect(batch.ranges.first?.previous == BlameOrigin(sha: Self.a, path: "f.txt"))
    }

    @Test("SHA-256 records and noise are read and skipped as they should")
    func sha256AndNoise() {
        let long = String(repeating: "c", count: 64)
        let text = "warning: something\n\(long) 1 1 1\nauthor C\nsummary S\nfilename x\nnot a record\n"

        let batch = BlameParser.parse(text)

        #expect(batch.commits.map(\.sha) == [long])
        #expect(batch.ranges.map(\.finalLine) == [1])
    }

    // MARK: Line mapping

    private static func hunk(old: Int, _ oldCount: Int, new: Int, _ newCount: Int) -> DiffHunk {
        DiffHunk(id: 0, oldStart: old, oldCount: oldCount, newStart: new, newCount: newCount, header: "", lines: [])
    }

    @Test("Lines above a change keep their number; lines below move by what it added or removed")
    func mappingAroundChanges() {
        // Line 3 deleted, two lines inserted after old line 6 (new 6–7).
        let hunks = [Self.hunk(old: 3, 1, new: 2, 0), Self.hunk(old: 6, 0, new: 6, 2)]

        #expect(BlameLineMapping.oldLine(forNewLine: 1, in: hunks) == 1)
        #expect(BlameLineMapping.oldLine(forNewLine: 2, in: hunks) == 2)
        #expect(BlameLineMapping.oldLine(forNewLine: 3, in: hunks) == 4)
        #expect(BlameLineMapping.oldLine(forNewLine: 5, in: hunks) == 6)
        // The inserted lines go to where they were inserted.
        #expect(BlameLineMapping.oldLine(forNewLine: 6, in: hunks) == 6)
        #expect(BlameLineMapping.oldLine(forNewLine: 7, in: hunks) == 6)
        #expect(BlameLineMapping.oldLine(forNewLine: 8, in: hunks) == 7)
    }

    @Test("A line inside a replacement goes to the same place in what it replaced")
    func mappingInsideReplacement() {
        // Old lines 4–5 replaced by new lines 4–7.
        let hunks = [Self.hunk(old: 4, 2, new: 4, 4)]

        #expect(BlameLineMapping.oldLine(forNewLine: 4, in: hunks) == 4)
        #expect(BlameLineMapping.oldLine(forNewLine: 5, in: hunks) == 5)
        #expect(BlameLineMapping.oldLine(forNewLine: 7, in: hunks) == 5)
        #expect(BlameLineMapping.oldLine(forNewLine: 8, in: hunks) == 6)
        #expect(BlameLineMapping.oldLine(forNewLine: 9, in: []) == 9)
    }

    @Test("Lines added at the very top map to line 1")
    func mappingTop() {
        let hunks = [Self.hunk(old: 0, 0, new: 1, 3)]

        #expect(BlameLineMapping.oldLine(forNewLine: 2, in: hunks) == 1)
        #expect(BlameLineMapping.oldLine(forNewLine: 4, in: hunks) == 1)
        #expect(BlameLineMapping.oldLine(forNewLine: 5, in: hunks) == 2)
    }
}
