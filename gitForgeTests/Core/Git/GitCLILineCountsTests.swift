import Foundation
import Testing
@testable import gitForge

@Suite("GitCLI — per-file line counts", .serialized)
struct GitCLILineCountsTests {

    @Test("parseNumstat reads plain, renamed and binary records")
    func parsesRecords() {
        let raw = "3\t1\tSources/a.swift\0" + "2\t0\t\0old name.txt\0new name.txt\0" + "-\t-\timage.png\0"
        let counts = GitCLI.parseNumstat(raw)
        #expect(counts["Sources/a.swift"] == DiffStats(additions: 3, deletions: 1))
        #expect(counts["new name.txt"] == DiffStats(additions: 2, deletions: 0))
        #expect(counts["old name.txt"] == nil)
        #expect(counts["image.png"] == nil)
        #expect(GitCLI.parseNumstat("").isEmpty)
    }

    @Test("Staged and unstaged counts come from their own side")
    func stagedAndUnstaged() async throws {
        let repo = try GitTestRepo()
        defer { repo.remove() }
        try repo.commit("init", files: ["a.txt": "1\n2\n3\n"])
        try repo.write("1\n2\n3\n4\n", to: "a.txt")
        try repo.git("add", "a.txt")
        try repo.write("1\n3\n4\n5\n6\n", to: "a.txt")

        let staged = try await repo.cli.lineCounts(staged: true)
        let unstaged = try await repo.cli.lineCounts(staged: false)
        #expect(staged["a.txt"] == DiffStats(additions: 1, deletions: 0))
        #expect(unstaged["a.txt"] == DiffStats(additions: 2, deletions: 1))
    }

    @Test("A staged rename is keyed by its new path")
    func stagedRename() async throws {
        let repo = try GitTestRepo()
        defer { repo.remove() }
        try repo.commit("init", files: ["old.txt": "a\nb\nc\nd\ne\n"])
        try repo.git("mv", "old.txt", "new.txt")
        try repo.write("a\nb\nc\nd\ne\nf\n", to: "new.txt")
        try repo.git("add", "new.txt")

        let staged = try await repo.cli.lineCounts(staged: true)
        #expect(staged["new.txt"] == DiffStats(additions: 1, deletions: 0))
    }
}
