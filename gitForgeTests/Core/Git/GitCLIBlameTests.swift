import Foundation
import Testing
@testable import gitForge

/// `GitCLI.blame` and friends over real repositories: boundary commits,
/// uncommitted lines, moved and copied lines, renames, and the mapping
/// "Blame before this commit" uses.
@Suite("GitCLI.blame", .serialized)
struct GitCLIBlameTests {

    private static func sha(_ repo: GitTestRepo, _ rev: String) async throws -> String {
        try await repo.gitAsync("rev-parse", rev).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Reads the whole stream.
    private static func blame(_ repo: GitTestRepo, _ path: String, at revision: String? = nil,
                              ignoringWhitespace: Bool = false) async throws -> BlameParser.Batch {
        var all = BlameParser.Batch()
        for try await batch in repo.cli.blame(path: path, revision: revision, ignoreWhitespace: ignoringWhitespace) {
            all.commits += batch.commits
            all.ranges += batch.ranges
        }
        return all
    }

    /// The SHA blamed for each line, 1-based, from the ranges.
    private static func shaByLine(_ batch: BlameParser.Batch, lines: Int) -> [String?] {
        var result = [String?](repeating: nil, count: lines)
        for range in batch.ranges {
            for line in range.finalLine..<(range.finalLine + range.count) where line - 1 < lines {
                result[line - 1] = range.sha
            }
        }
        return result
    }

    @Test("Each line goes to the commit that last changed it; the root commit is a boundary with no parent")
    func basic() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("first", files: ["f.txt": "one\ntwo\nthree\n"])
            try repo.commit("second", files: ["f.txt": "one\nTWO\nthree\n"])
        }
        defer { repo.remove() }
        let first = try await Self.sha(repo, "HEAD~1")
        let second = try await Self.sha(repo, "HEAD")

        let batch = try await Self.blame(repo, "f.txt", at: "HEAD")

        #expect(Self.shaByLine(batch, lines: 3) == [first, second, first])
        let root = try #require(batch.commits.first { $0.sha == first })
        #expect(root.isBoundary)
        #expect(root.summary == "first")
        #expect(root.authorName == "Test")
        #expect(batch.ranges.filter { $0.sha == first }.allSatisfy { $0.previous == nil })
        let change = try #require(batch.ranges.first { $0.sha == second })
        #expect(change.previous == BlameOrigin(sha: first, path: "f.txt"))
        #expect(change.path == "f.txt")
        #expect(batch.commits.filter { $0.sha == second }.count == 1)
    }

    @Test("Uncommitted lines in the working tree are blamed on the all-zero SHA, with HEAD before them")
    func uncommittedLines() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("first", files: ["f.txt": "one\ntwo\nthree\n"])
            try repo.write("one\nlocal edit\nthree\nadded\n", to: "f.txt")
        }
        defer { repo.remove() }
        let head = try await Self.sha(repo, "HEAD")

        let batch = try await Self.blame(repo, "f.txt")

        let byLine = Self.shaByLine(batch, lines: 4)
        #expect(byLine[0] == head && byLine[2] == head)
        #expect(byLine[1].map(BlameCommit.isUncommitted) == true)
        #expect(byLine[3].map(BlameCommit.isUncommitted) == true)
        let uncommitted = try #require(batch.commits.first { $0.isUncommitted })
        #expect(uncommitted.authorName == "Not Committed Yet")
        let range = try #require(batch.ranges.first { $0.sha == uncommitted.sha })
        #expect(range.previous?.sha == head)
    }

    @Test("Lines moved from another file in the same commit are blamed on where they came from (-C)")
    func movedLines() async throws {
        let block = (1...8).map { "let value\($0) = compute(\($0)) // a line long enough to be recognised" }
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("write helpers", files: ["helpers.swift": block.joined(separator: "\n") + "\n",
                                                     "main.swift": "print(1)\n"])
            try repo.write("print(1)\n" + block.joined(separator: "\n") + "\n", to: "main.swift")
            try repo.write("// empty now\n", to: "helpers.swift")
            try repo.git("add", "-A")
            try repo.git("commit", "-q", "-m", "move helpers into main")
        }
        defer { repo.remove() }
        let original = try await Self.sha(repo, "HEAD~1")

        let batch = try await Self.blame(repo, "main.swift", at: "HEAD")

        let moved = batch.ranges.filter { $0.finalLine >= 2 }
        #expect(!moved.isEmpty)
        #expect(moved.allSatisfy { $0.sha == original })
        #expect(moved.allSatisfy { $0.path == "helpers.swift" })
        #expect(moved.first?.sourceLine == 1)
    }

    @Test("Lines moved within the file keep their commit (-M)")
    func movedWithinFile() async throws {
        let top = (1...6).map { "top line number \($0) with enough text to match" }
        let bottom = (1...6).map { "bottom line number \($0) with enough text to match" }
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("write", files: ["f.txt": (top + bottom).joined(separator: "\n") + "\n"])
            try repo.commit("swap halves", files: ["f.txt": (bottom + top).joined(separator: "\n") + "\n"])
        }
        defer { repo.remove() }
        let written = try await Self.sha(repo, "HEAD~1")

        let batch = try await Self.blame(repo, "f.txt", at: "HEAD")

        #expect(Self.shaByLine(batch, lines: 12).allSatisfy { $0 == written })
    }

    @Test("After a rename, older lines name the old path, and the parent of the rename has it")
    func renamed() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("add", files: ["old.txt": "a\nb\nc\n"])
            try repo.git("mv", "old.txt", "new.txt")
            try repo.git("commit", "-q", "-m", "rename")
            try repo.commit("edit", files: ["new.txt": "a\nB\nc\n"])
        }
        defer { repo.remove() }
        let add = try await Self.sha(repo, "HEAD~2")

        let batch = try await Self.blame(repo, "new.txt", at: "HEAD")

        let old = try #require(batch.ranges.first { $0.sha == add })
        #expect(old.path == "old.txt")
        let edit = try #require(batch.ranges.first { $0.finalLine == 2 })
        #expect(edit.previous?.path == "new.txt")
    }

    @Test("-w blames a whitespace-only change on the commit before it")
    func ignoreWhitespace() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("first", files: ["f.txt": "if x {\ncall()\n}\n"])
            try repo.commit("indent", files: ["f.txt": "if x {\n    call()\n}\n"])
        }
        defer { repo.remove() }
        let first = try await Self.sha(repo, "HEAD~1")
        let indent = try await Self.sha(repo, "HEAD")

        #expect(Self.shaByLine(try await Self.blame(repo, "f.txt", at: "HEAD"), lines: 3)[1] == indent)
        #expect(Self.shaByLine(try await Self.blame(repo, "f.txt", at: "HEAD", ignoringWhitespace: true), lines: 3)[1] == first)
    }

    @Test("A path that isn't at the revision fails, and an option-like revision is refused")
    func failures() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("first", files: ["f.txt": "x\n"])
        }
        defer { repo.remove() }

        await #expect(throws: GitError.self) { try await Self.blame(repo, "missing.txt", at: "HEAD") }
        await #expect(throws: GitError.self) { try await Self.blame(repo, "f.txt", at: "--output=/tmp/x") }
    }

    @Test("Blaming 5,000 lines streams in more than one batch and covers every line")
    func streamsLargeFile() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("first", files: ["big.txt": (1...5_000).map { "line \($0)" }.joined(separator: "\n") + "\n"])
            var lines = (1...5_000).map { "line \($0)" }
            for index in stride(from: 0, to: 5_000, by: 2) { lines[index] = "changed \(index)" }
            try repo.commit("every other line", files: ["big.txt": lines.joined(separator: "\n") + "\n"])
        }
        defer { repo.remove() }

        var batches = 0
        var covered = 0
        for try await batch in repo.cli.blame(path: "big.txt", revision: "HEAD", ignoreWhitespace: false) {
            batches += 1
            covered += batch.ranges.reduce(0) { $0 + $1.count }
        }

        #expect(covered == 5_000)
        #expect(batches > 1)
    }

    // MARK: Source and mapping

    @Test("The source is the working tree's file, or the file at a revision; binary files are spotted")
    func source() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("first", files: ["f.txt": "one\ntwo\n"])
            try repo.write(Data([0x89, 0x50, 0x00, 0x01]), to: "bin.dat")
            try repo.git("add", "bin.dat")
            try repo.git("commit", "-q", "-m", "binary")
            try repo.write("one\ntwo\nthree\n", to: "f.txt")
        }
        defer { repo.remove() }

        #expect(try await repo.cli.blameSource(path: "f.txt", revision: nil) == .text(["one", "two", "three"]))
        #expect(try await repo.cli.blameSource(path: "f.txt", revision: "HEAD") == .text(["one", "two"]))
        #expect(try await repo.cli.blameSource(path: "bin.dat", revision: "HEAD") == .binary)
        await #expect(throws: (any Error).self) { try await repo.cli.blameSource(path: "nope.txt", revision: "HEAD") }
    }

    @Test("A line moves to the parent across the commit's change, renames included")
    func lineBefore() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("first", files: ["a.txt": "1\n2\n3\n4\n5\n6\n"])
            try repo.git("mv", "a.txt", "b.txt")
            try repo.write("0\n1\n2\n3\nfour\n5\n6\n", to: "b.txt")
            try repo.git("add", "-A")
            try repo.git("commit", "-q", "-m", "rename, add a line on top, change 4")
        }
        defer { repo.remove() }
        let parent = try await Self.sha(repo, "HEAD~1")
        let head = try await Self.sha(repo, "HEAD")

        // "6" is line 7 now, line 6 before; "four" (line 5) was "4" (line 4).
        #expect(await repo.cli.lineBefore(7, path: "b.txt", at: head, parent: parent, parentPath: "a.txt") == 6)
        #expect(await repo.cli.lineBefore(5, path: "b.txt", at: head, parent: parent, parentPath: "a.txt") == 4)
        #expect(await repo.cli.lineBefore(1, path: "b.txt", at: head, parent: parent, parentPath: "a.txt") == 1)
    }
}
