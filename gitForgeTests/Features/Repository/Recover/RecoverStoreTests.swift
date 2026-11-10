import Foundation
import Testing
@testable import gitForge

/// `RecoverStore` over a real repo: what the Recover sheet lists, selects
/// and shows, and how it follows a reload after an action.
@Suite("Recover lost commits", .serialized)
@MainActor
struct RecoverStoreTests {

    /// one … five on main, then `reset --hard HEAD~3`.
    private static func resetRepo() async throws -> GitTestRepo {
        try await GitTestRepo.make { repo in
            for n in ["one", "two", "three", "four", "five"] {
                try repo.commit(n, files: ["\(n).txt": n])
            }
            try repo.git("reset", "-q", "--hard", "HEAD~3")
        }
    }

    @Test("Opening it selects the state before the reset, with its files, first diff and the commits it brings back")
    func opensOnLatest() async throws {
        let repo = try await Self.resetRepo()
        defer { repo.remove() }
        let store = RecoverStore(cli: repo.cli)

        await store.load(.head)

        let selected = try #require(store.selectedEntry)
        #expect(selected.index == 0)
        #expect(selected.title.hasPrefix("Before reset to "))
        #expect(selected.commit.subject == "five")
        #expect(store.lostCount(of: selected) == 3)
        #expect(store.detail?.commit.sha == selected.commit.sha)
        #expect(store.detail?.files.map(\.path) == ["five.txt"])
        #expect(store.selectedFile == "five.txt")
        #expect(store.fileDiff.flatMap(\.lines).contains { $0.content == "five" })
        #expect(!store.isLoading && !store.isLoadingDetail && !store.isLoadingFileDiff)
        #expect(store.hasLoaded && store.loadError == nil)
    }

    @Test("After a branch is created on it, the entry stays selected and nothing is lost any more")
    func reloadAfterBranch() async throws {
        let repo = try await Self.resetRepo()
        defer { repo.remove() }
        let store = RecoverStore(cli: repo.cli)
        await store.load(.head)
        let entry = try #require(store.selectedEntry)

        try await repo.cli.createBranch(entry.suggestedBranchName(), startingAt: entry.commit.sha)
        await store.reload()

        #expect(store.selectedEntry?.commit.sha == entry.commit.sha)
        #expect(store.lostCount(of: entry) == 0)
    }

    @Test("A move on top (a reset from the sheet) shifts the indexes; the selection follows its entry")
    func selectionFollowsEntry() async throws {
        let repo = try await Self.resetRepo()
        defer { repo.remove() }
        let store = RecoverStore(cli: repo.cli)
        await store.load(.head)
        let three = try #require(store.entries.first { $0.commit.subject == "three" })
        await store.select(three)
        #expect(store.selectedEntry?.index == three.index)

        try await repo.gitAsync("reset", "-q", "--hard", three.commit.sha)
        await store.reload()

        #expect(store.selectedEntry?.index == three.index + 1)
        #expect(store.selectedEntry?.commit.subject == "three")
        #expect(store.entries.first?.title.hasPrefix("Before reset to ") == true)
    }

    @Test("Picking a branch lists its reflog and selects its newest entry")
    func branchSource() async throws {
        let repo = try await Self.resetRepo()
        defer { repo.remove() }
        try await repo.perform { repo in
            try repo.git("checkout", "-q", "-b", "side")
            try repo.commit("s1", files: ["s.txt": "1"])
            try repo.git("checkout", "-q", "main")
        }
        let store = RecoverStore(cli: repo.cli)
        await store.load(.head)

        await store.load(.branch("side"))

        #expect(store.source == .branch("side"))
        #expect(store.entries.map(\.action) == [.commit, .branchCreated(from: "HEAD")])
        #expect(store.selectedEntry?.commit.subject == "s1")
        #expect(store.detail?.commit.subject == "s1")
    }

    @Test("Choosing another file loads its diff; an entry on the same commit keeps it open")
    func fileSelection() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("base", files: ["a.txt": "a"])
            try repo.commit("two files", files: ["a.txt": "a2", "b.txt": "b"])
            try repo.git("checkout", "-q", "-b", "same")
        }
        defer { repo.remove() }
        let store = RecoverStore(cli: repo.cli)
        await store.load(.head)
        #expect(store.selectedFile == "a.txt")

        await store.selectFile("b.txt")
        #expect(store.selectedFile == "b.txt")
        #expect(store.fileDiff.flatMap(\.lines).contains { $0.content == "b" })

        // HEAD@{1} (the commit) is the same commit as HEAD@{0} (the checkout).
        let commitEntry = try #require(store.entries.dropFirst().first)
        #expect(commitEntry.commit.sha == store.selectedEntry?.commit.sha)
        await store.select(commitEntry)
        #expect(store.selectedEntryId == commitEntry.id)
        #expect(store.selectedFile == "b.txt")
    }

    @Test("An empty repository lists nothing and selects nothing")
    func emptyRepo() async throws {
        let repo = try await GitTestRepo.make()
        defer { repo.remove() }
        let store = RecoverStore(cli: repo.cli)
        await store.load(.head)
        #expect(store.entries.isEmpty)
        #expect(store.selectedEntry == nil)
        #expect(store.detail == nil)
        #expect(store.hasLoaded && store.loadError == nil)
    }
}
