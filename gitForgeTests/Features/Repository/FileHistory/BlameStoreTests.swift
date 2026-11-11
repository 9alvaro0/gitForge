import Foundation
import Testing
@testable import gitForge

/// `BlameStore` over real repositories: what the Blame view shows, how it
/// groups lines, and "Blame before this commit".
@Suite("Blame store", .serialized)
@MainActor
struct BlameStoreTests {

    private static func sha(_ repo: GitTestRepo, _ rev: String) async throws -> String {
        try await repo.gitAsync("rev-parse", rev).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// f.txt: ten lines in "first"; "second" changes line 5 and adds two
    /// lines on top, so the old line 5 is line 7 now.
    private static func repo() async throws -> GitTestRepo {
        try await GitTestRepo.make { repo in
            try repo.commit("first", files: ["f.txt": (1...10).map { "line \($0)" }.joined(separator: "\n") + "\n"])
            var lines = (1...10).map { "line \($0)" }
            lines[4] = "line five"
            try repo.commit("second", files: ["f.txt": (["new a", "new b"] + lines).joined(separator: "\n") + "\n"])
        }
    }

    @Test("Loading shows every line, blamed and grouped by commit")
    func loads() async throws {
        let repo = try await Self.repo()
        defer { repo.remove() }
        let first = try await Self.sha(repo, "HEAD~1")
        let second = try await Self.sha(repo, "HEAD")
        let store = BlameStore(cli: repo.cli, location: .init(revision: "HEAD", path: "f.txt"))
        store.ignoresWhitespace = { false }

        await store.load(store.location)

        #expect(store.phase == .loaded)
        #expect(store.lines.count == 12)
        #expect(store.lines[6] == "line five")
        #expect(store.blamedLineCount == 12)
        #expect(store.progress == 1)
        #expect(!store.isBlaming)
        #expect((1...12).map { store.sha(at: $0) }
                == [second, second, first, first, first, first, second, first, first, first, first, first])
        #expect((1...12).filter { store.startsGroup($0) } == [1, 3, 7, 8])
        #expect(store.commit(at: 7)?.summary == "second")
        #expect(store.commit(at: 3)?.isBoundary == true)
        #expect(store.origin(before: 3) == nil)
        #expect(store.origin(before: 7) == BlameOrigin(sha: first, path: "f.txt"))
    }

    @Test("Blame before this commit opens the parent with the line it came from, and Back returns")
    func blameBefore() async throws {
        let repo = try await Self.repo()
        defer { repo.remove() }
        let first = try await Self.sha(repo, "HEAD~1")
        let store = BlameStore(cli: repo.cli, location: .init(revision: "HEAD", path: "f.txt"))
        store.ignoresWhitespace = { false }
        await store.load(store.location)

        await store.blameBefore(line: 7)

        #expect(store.location == .init(revision: first, path: "f.txt", line: 5))
        #expect(store.focusLine == 5)
        #expect(store.selectedLine == 5)
        #expect(store.lines[4] == "line 5")
        #expect(store.backStack == [.init(revision: "HEAD", path: "f.txt", line: 7)])

        await store.goBack()

        #expect(store.location == .init(revision: "HEAD", path: "f.txt", line: 7))
        #expect(store.focusLine == 7)
        #expect(store.backStack.isEmpty)
    }

    @Test("A line of the root commit has nothing before it")
    func boundary() async throws {
        let repo = try await Self.repo()
        defer { repo.remove() }
        let store = BlameStore(cli: repo.cli, location: .init(revision: "HEAD", path: "f.txt"))
        await store.load(store.location)

        await store.blameBefore(line: 3)

        #expect(store.location.revision == "HEAD")
        #expect(store.backStack.isEmpty)
    }

    @Test("Uncommitted lines are marked, and blaming before them opens HEAD at the same place")
    func uncommitted() async throws {
        let repo = try await Self.repo()
        defer { repo.remove() }
        let head = try await Self.sha(repo, "HEAD")
        var lines = try #require(repo.read("f.txt")).split(separator: "\n").map(String.init)
        lines.insert("typed just now", at: 0)
        lines[7] = "line five, edited"
        let edited = lines.joined(separator: "\n") + "\n"
        try await repo.perform { try $0.write(edited, to: "f.txt") }
        let store = BlameStore(cli: repo.cli, location: .init(revision: nil, path: "f.txt"))
        await store.load(store.location)

        #expect(store.commit(at: 1)?.isUncommitted == true)
        #expect(store.commit(at: 8)?.isUncommitted == true)
        #expect(store.commit(at: 2)?.isUncommitted == false)

        await store.blameBefore(line: 8)

        #expect(store.location.revision == head)
        #expect(store.location.line == 7)
        #expect(store.lines[6] == "line five")
    }

    @Test("An untracked file can't be blamed, and says why")
    func untracked() async throws {
        let repo = try await Self.repo()
        defer { repo.remove() }
        try await repo.perform { try $0.write("new\n", to: "new.txt") }
        let store = BlameStore(cli: repo.cli, location: .init(revision: nil, path: "new.txt"))

        await store.load(store.location)

        #expect(store.phase == .failed("This file isn’t committed yet, so there is nothing to blame."))
        #expect(!store.isBlaming)
    }

    @Test("A newer load replaces one still streaming")
    func replaced() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("one", files: ["big.txt": (1...3_000).map { "row \($0)" }.joined(separator: "\n") + "\n",
                                           "small.txt": "s\n"])
        }
        defer { repo.remove() }
        let store = BlameStore(cli: repo.cli, location: .init(revision: "HEAD", path: "big.txt"))

        let big = Task { await store.load(.init(revision: "HEAD", path: "big.txt")) }
        // Wait until the big file is read and its blame has started.
        while store.lines.count != 3_000 { await Task.yield() }
        await store.load(.init(revision: "HEAD", path: "small.txt"))
        await big.value

        #expect(store.location.path == "small.txt")
        #expect(store.lines == ["s"])
        #expect(store.blamedLineCount == 1)
    }
}
