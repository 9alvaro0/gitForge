import Foundation
import Testing
@testable import gitForge

/// `FileHistoryStore` over a real repo: what the File history sheet lists,
/// pages and shows for the selected commit.
@Suite("File history store", .serialized)
@MainActor
struct FileHistoryStoreTests {

    /// a.txt: add, three edits, a rename to b.txt, one more edit.
    private static func repo() async throws -> GitTestRepo {
        try await GitTestRepo.make { repo in
            try repo.commit("add", files: ["a.txt": "1\n2\n3\n4\n5\n6\n"])
            try repo.commit("edit 1", files: ["a.txt": "one\n2\n3\n4\n5\n6\n"])
            try repo.commit("edit 2", files: ["a.txt": "one\ntwo\n3\n4\n5\n6\n"])
            try repo.commit("edit 3", files: ["a.txt": "one\ntwo\nthree\n4\n5\n6\n"])
            try repo.git("mv", "a.txt", "b.txt")
            try repo.git("commit", "-q", "-m", "rename")
            try repo.commit("edit 4", files: ["b.txt": "one\ntwo\nthree\nfour\n5\n6\n"])
        }
    }

    @Test("Opening it lists the newest page, selects the newest commit and shows the file's diff in it")
    func opensOnNewest() async throws {
        let repo = try await Self.repo()
        defer { repo.remove() }
        let store = FileHistoryStore(cli: repo.cli, path: "b.txt")

        await store.load()

        #expect(store.entries.map(\.commit.subject) == ["edit 4", "rename", "edit 3", "edit 2", "edit 1", "add"])
        #expect(store.selectedEntry?.commit.subject == "edit 4")
        let changed = store.fileDiff.flatMap(\.lines).filter { $0.kind != .context }.map(\.content)
        #expect(changed == ["4", "four"])
        #expect(store.renames.map(\.previousPath) == ["a.txt"])
        #expect(store.hasLoaded && !store.isLoading && !store.isLoadingFileDiff && store.loadError == nil)
        #expect(!store.hasMore)
    }

    @Test("Pages load as the last entry shows, until a page comes back short")
    func pages() async throws {
        let repo = try await Self.repo()
        defer { repo.remove() }
        let store = FileHistoryStore(cli: repo.cli, path: "b.txt")
        store.pageSize = { 4 }

        await store.load()
        #expect(store.entries.count == 4)
        #expect(store.hasMore)

        // Not the last row: nothing to do.
        await store.loadMoreIfNeeded(after: store.entries[0])
        #expect(store.entries.count == 4)

        await store.loadMoreIfNeeded(after: try #require(store.entries.last))
        #expect(store.entries.map(\.commit.subject) == ["edit 4", "rename", "edit 3", "edit 2", "edit 1", "add"])
        #expect(!store.hasMore)
    }

    @Test("Selecting an entry before the rename shows that commit's diff under the old name")
    func selectsOlderEntry() async throws {
        let repo = try await Self.repo()
        defer { repo.remove() }
        let store = FileHistoryStore(cli: repo.cli, path: "b.txt")
        await store.load()

        let entry = try #require(store.entries.first { $0.commit.subject == "edit 2" })
        await store.select(entry)

        #expect(store.selectedEntry?.path == "a.txt")
        let changed = store.fileDiff.flatMap(\.lines).filter { $0.kind != .context }.map(\.content)
        #expect(changed == ["2", "two"])
        #expect(await store.newSideLines()?.prefix(2) == ["one", "two"])
    }

    @Test("Opening it on a commit selects that commit")
    func opensOnCommit() async throws {
        let repo = try await Self.repo()
        defer { repo.remove() }
        let sha = try await repo.gitAsync("rev-parse", "HEAD~3").trimmingCharacters(in: .whitespacesAndNewlines)
        let store = FileHistoryStore(cli: repo.cli, path: "b.txt")

        await store.load(selecting: sha)

        #expect(store.selectedEntry?.commit.subject == "edit 2")
    }

    @Test("The rename's own entry reads as a rename with no content change")
    func renameEntry() async throws {
        let repo = try await Self.repo()
        defer { repo.remove() }
        let store = FileHistoryStore(cli: repo.cli, path: "b.txt")
        await store.load()

        let rename = try #require(store.entries.first { $0.commit.subject == "rename" })
        await store.select(rename)

        #expect(store.fileDiff.isEmpty)
        #expect(store.fileDiffEmptyState == .renameOnly)
    }
}
