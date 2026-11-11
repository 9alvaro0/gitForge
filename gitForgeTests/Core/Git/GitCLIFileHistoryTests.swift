import Foundation
import Testing
@testable import gitForge

/// `GitCLI.fileHistory` over real repositories: renames, a file deleted and
/// recreated, paging, and the diff of one entry.
@Suite("GitCLI.fileHistory", .serialized)
struct GitCLIFileHistoryTests {

    private static func sha(_ repo: GitTestRepo, _ rev: String) async throws -> String {
        try await repo.gitAsync("rev-parse", rev).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// add old.txt → edit it → `git mv` to dir/new.txt → edit dir/new.txt,
    /// with an unrelated commit in between.
    private static func renamedFile() async throws -> GitTestRepo {
        try await GitTestRepo.make { repo in
            try repo.commit("add old", files: ["old.txt": "a\nb\nc\n"])
            try repo.commit("edit old", files: ["old.txt": "a\nb\nc\nd\n"])
            try repo.commit("unrelated", files: ["other.txt": "x\n"])
            try repo.git("mv", "old.txt", "new.txt")
            try FileManager.default.createDirectory(at: repo.url.appendingPathComponent("dir"),
                                                    withIntermediateDirectories: true)
            try repo.git("mv", "new.txt", "dir/new.txt")
            try repo.git("commit", "-q", "-m", "move to dir")
            try repo.commit("edit new", files: ["dir/new.txt": "a\nB\nc\nd\n"])
        }
    }

    // MARK: Renames

    @Test("The history of a renamed file includes the commits before the rename, under the old name")
    func followsRenames() async throws {
        let repo = try await Self.renamedFile()
        defer { repo.remove() }

        let entries = try await repo.cli.fileHistory(path: "dir/new.txt", limit: 50)

        #expect(entries.map(\.commit.subject) == ["edit new", "move to dir", "edit old", "add old"])
        #expect(entries.map(\.path) == ["dir/new.txt", "dir/new.txt", "old.txt", "old.txt"])
        #expect(entries[0].status == .modified)
        #expect(entries[1].status == .renamed(from: "old.txt"))
        #expect(entries[1].previousPath == "old.txt")
        #expect(entries[2].status == .modified)
        #expect(entries[3].status == .added)
        // The commit on another file isn't listed.
        #expect(!entries.contains { $0.commit.subject == "unrelated" })
    }

    @Test("Each entry carries its commit: SHA, parents, author and date")
    func entryCommit() async throws {
        let repo = try await Self.renamedFile()
        defer { repo.remove() }
        let head = try await Self.sha(repo, "HEAD")
        let parent = try await Self.sha(repo, "HEAD~1")

        let first = try #require(try await repo.cli.fileHistory(path: "dir/new.txt", limit: 1).first)

        #expect(first.commit.sha == head)
        #expect(first.commit.parentShas == [parent])
        #expect(first.commit.authorName == "Test")
        #expect(first.commit.authorEmail == "test@example.com")
        #expect(first.commit.authorDate != GitCLI.unknownAuthorDate)
    }

    @Test("A rename's diff pairs both paths: only the edited lines, not a whole new file")
    func renameDiff() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("add", files: ["a.txt": (1...20).map { "line \($0)" }.joined(separator: "\n") + "\n"])
            try repo.git("mv", "a.txt", "b.txt")
            var lines = (1...20).map { "line \($0)" }
            lines[9] = "line ten"
            try repo.write(lines.joined(separator: "\n") + "\n", to: "b.txt")
            try repo.git("add", "-A")
            try repo.git("commit", "-q", "-m", "rename and edit")
        }
        defer { repo.remove() }

        let entry = try #require(try await repo.cli.fileHistory(path: "b.txt", limit: 1).first)
        #expect(entry.status == .renamed(from: "a.txt"))
        let raw = try await repo.cli.fileHistoryDiff(sha: entry.commit.sha, path: entry.path,
                                                     previousPath: entry.previousPath)
        let hunks = DiffParser.parse(raw)

        let changed = hunks.flatMap(\.lines).filter { $0.kind != .context }
        #expect(changed.map(\.content) == ["line 10", "line ten"])
    }

    @Test("A pure rename has no hunks and reads as renamed")
    func pureRenameDiff() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("add", files: ["a.txt": "same\ncontent\nhere\n"])
            try repo.git("mv", "a.txt", "b.txt")
            try repo.git("commit", "-q", "-m", "rename")
        }
        defer { repo.remove() }

        let entry = try #require(try await repo.cli.fileHistory(path: "b.txt", limit: 1).first)
        let raw = try await repo.cli.fileHistoryDiff(sha: entry.commit.sha, path: entry.path,
                                                     previousPath: entry.previousPath)

        #expect(DiffParser.parse(raw).isEmpty)
        #expect(DiffEmptyState.classifying(raw: raw) == .renameOnly)
    }

    // MARK: Deleted and recreated

    @Test("A file deleted and recreated lists the deletion, then the old file's commits")
    func deletedAndRecreated() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("first version", files: ["f.txt": "one\n"])
            try repo.commit("edit first", files: ["f.txt": "one\ntwo\n"])
            try repo.git("rm", "-q", "f.txt")
            try repo.git("commit", "-q", "-m", "delete")
            try repo.commit("second version", files: ["f.txt": "fresh\n"])
        }
        defer { repo.remove() }

        let entries = try await repo.cli.fileHistory(path: "f.txt", limit: 50)

        #expect(entries.map(\.commit.subject) == ["second version", "delete", "edit first", "first version"])
        #expect(entries.map(\.status) == [.added, .deleted, .modified, .added])
        #expect(entries.allSatisfy { $0.path == "f.txt" })
        #expect(entries[1].isDeletion)
    }

    @Test("A deleted file still has its history")
    func deletedFile() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("add", files: ["gone.txt": "x\n", "keep.txt": "k\n"])
            try repo.git("rm", "-q", "gone.txt")
            try repo.git("commit", "-q", "-m", "remove")
        }
        defer { repo.remove() }

        let entries = try await repo.cli.fileHistory(path: "gone.txt", limit: 50)

        #expect(entries.map(\.status) == [.deleted, .added])
    }

    // MARK: Paging and edge cases

    @Test("A short walk is the top of a longer one, across the rename")
    func paging() async throws {
        let repo = try await Self.renamedFile()
        defer { repo.remove() }

        let all = try await repo.cli.fileHistory(path: "dir/new.txt", limit: 50)
        let first = try await repo.cli.fileHistory(path: "dir/new.txt", limit: 2)
        let longer = try await repo.cli.fileHistory(path: "dir/new.txt", limit: 4)

        #expect(first.map(\.commit.sha) == Array(all.prefix(2)).map(\.commit.sha))
        #expect(longer.map(\.commit.sha) == all.map(\.commit.sha))
    }

    /// Why pages aren't read with `--skip`: git only follows a rename in a
    /// commit it shows. If this starts passing, `--skip` became an option.
    @Test("--skip over the rename loses the commits before it")
    func skipLosesRename() async throws {
        let repo = try await Self.renamedFile()
        defer { repo.remove() }

        let skipped = try await repo.gitAsync("log", "--follow", "--format=%s", "--skip", "2", "-n", "2",
                                              "HEAD", "--", "dir/new.txt")

        #expect(!skipped.contains("edit old"))
    }

    @Test("Paths with spaces and non-ASCII letters come back as written")
    func unusualPath() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("add", files: ["docs/café menu.txt": "v1\n"])
            try repo.commit("edit", files: ["docs/café menu.txt": "v2\n"])
        }
        defer { repo.remove() }

        let entries = try await repo.cli.fileHistory(path: "docs/café menu.txt", limit: 50)

        #expect(entries.map(\.path) == ["docs/café menu.txt", "docs/café menu.txt"])
    }

    @Test("A repository with no commits has no history instead of failing")
    func unbornHead() async throws {
        let repo = try await GitTestRepo.make()
        defer { repo.remove() }

        let entries = try await repo.cli.fileHistory(path: "anything.txt", limit: 50)

        #expect(entries.isEmpty)
    }

    @Test("A file no commit touched has no history")
    func untouchedPath() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("add", files: ["a.txt": "a\n"])
        }
        defer { repo.remove() }

        #expect(try await repo.cli.fileHistory(path: "missing.txt", limit: 50).isEmpty)
    }

    @Test("Tracked files are listed once each, conflicted or not, up to the limit")
    func trackedFiles() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("add", files: ["a.txt": "a\n", "b/c.txt": "c\n", "d.txt": "d\n"])
        }
        defer { repo.remove() }

        #expect(try await repo.cli.trackedFiles(limit: 10) == ["a.txt", "b/c.txt", "d.txt"])
        #expect(try await repo.cli.trackedFiles(limit: 2) == ["a.txt", "b/c.txt"])
    }

    // MARK: Parser

    @Test("A merge with no name-status keeps the path of the entry above it")
    func parserMergeWithoutStatus() {
        let sha1 = String(repeating: "1", count: 40)
        let sha2 = String(repeating: "2", count: 40)
        let sha3 = String(repeating: "3", count: 40)
        let date = "2026-11-10T12:00:00+01:00"
        let output = "\(sha1)\u{1F}\(sha2)\u{1F}A\u{1F}a@x\u{1F}\(date)\u{1F}rename\0"
            + "\nR087\0src/old name.swift\0src/new.swift\0"
            + "\(sha2)\u{1F}\(sha3) \(sha1)\u{1F}A\u{1F}a@x\u{1F}\(date)\u{1F}Merge branch 'x'\0"
            + "\(sha3)\u{1F}\u{1F}A\u{1F}a@x\u{1F}\(date)\u{1F}add\0"
            + "\nA\0src/old name.swift\0"

        let entries = GitCLI.parseFileHistory(output, path: "src/new.swift")

        #expect(entries.map(\.commit.sha) == [sha1, sha2, sha3])
        #expect(entries[0].status == .renamed(from: "src/old name.swift"))
        #expect(entries[0].path == "src/new.swift")
        #expect(entries[1].status == nil)
        #expect(entries[1].path == "src/old name.swift")
        #expect(entries[1].commit.parentShas == [sha3, sha1])
        #expect(entries[2].status == .added)
        #expect(entries[2].commit.parentShas.isEmpty)
    }

    @Test("A copy carries where it came from; a subject with a unit separator stays whole")
    func parserCopyAndSubject() {
        let sha = String(repeating: "a", count: 40)
        let output = "\(sha)\u{1F}\u{1F}A\u{1F}a@x\u{1F}2026-11-10T12:00:00Z\u{1F}odd\u{1F}subject\0"
            + "\nC100\0template.txt\0copy.txt\0"

        let entry = GitCLI.parseFileHistory(output, path: "copy.txt").first

        #expect(entry?.status == .copied(from: "template.txt"))
        #expect(entry?.previousPath == "template.txt")
        #expect(entry?.commit.subject == "odd\u{1F}subject")
    }

    @Test("Empty output is no history")
    func parserEmpty() {
        #expect(GitCLI.parseFileHistory("", path: "a").isEmpty)
    }
}
