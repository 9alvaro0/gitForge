import Foundation
import Testing
@testable import gitForge

/// `HistorySearchStore` (#62) over real repositories: it finds commits below the loaded
/// pages, pages its results, supersedes and stops searches, gives the graph its selection
/// back and reveals a result in the graph.
@Suite("HistorySearchStore — git-backed History search", .serialized)
@MainActor
struct HistorySearchStoreTests {

    /// The refs a store reads, as `RepositoryViewModel` keeps them.
    final class Refs: HistoryRefsSource {
        var stashes: [Stash] = []
        var unmergedLocalBranchRefs: [String] = []
        var refsBySha: [String: [GitRef]] = [:]
        var refs: [GitRef] = []
        var remoteHeads: [String: String] = [:]
        var headSha: String?
        var hasUncommittedChanges = false
    }

    /// A linear history of `count` commits, "commit 1 first" the oldest. Commits divisible
    /// by 3 are by Bo, the rest by Ana; commit 1 adds `needle` to `old.txt`.
    private static func makeRepo(count: Int = 12) async throws -> GitTestRepo {
        try await GitTestRepo.make { repo in
            for index in 1...count {
                let author = index % 3 == 0 ? "Bo Li <bo@example.com>" : "Ana Pérez <ana@example.com>"
                try repo.write(index == 1 ? "needle\n" : "\(index)\n", to: index == 1 ? "old.txt" : "file.txt")
                try repo.git("add", "-A")
                let date = "\(1_700_000_000 + index * 60) +0000"
                let message = index == 1 ? "commit 1 first" : "commit \(index)"
                try repo.git(["commit", "-q", "-m", message, "--author", author],
                             extraEnvironment: ["GIT_AUTHOR_DATE": date, "GIT_COMMITTER_DATE": date])
            }
        }
    }

    /// A store over `repo` with pages of `pageSize`, its first page loaded.
    private static func makeStore(_ repo: GitTestRepo, pageSize: Int = 3) async -> (HistoryStore, Refs) {
        let refs = Refs()
        let suite = TestDefaults()
        let store = HistoryStore(cli: repo.cli, tasks: OwnedTasks(), repositoryURL: repo.url, defaults: suite.defaults)
        suite.remove()
        store.pageSize = { pageSize }
        store.refsSource = refs
        await store.loadInitial()
        return (store, refs)
    }

    private static func search(_ store: HistoryStore, _ query: HistorySearchQuery) async {
        store.search.draft = query
        store.search.run()
        await store.search.waitForSearch()
    }

    @Test("A commit below the loaded pages is found by message, author, content and path")
    func findsOlderCommits() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        let (store, _) = await Self.makeStore(repo)
        #expect(store.commits.map(\.subject) == ["commit 12", "commit 11", "commit 10"])

        for query in [HistorySearchQuery(message: "FIRST"), HistorySearchQuery(content: "needle"),
                      HistorySearchQuery(path: "old.txt"),
                      HistorySearchQuery(message: "first", author: "ANA@example.com", content: "need", path: "old.txt")] {
            await Self.search(store, query)
            #expect(store.search.results.map(\.subject) == ["commit 1 first"], "\(query)")
            #expect(store.search.activeQuery == query.normalized)
            #expect(store.search.error == nil)
        }
        // Commit 1 isn't loaded, yet selecting it shows it: the inspector reads it from the results.
        let oldest = try #require(store.search.results.last)
        #expect(store.commitsById[oldest.id] == nil)
        store.selectedCommitId = oldest.id
        #expect(store.selectedCommit == oldest)
    }

    @Test("Results page with the log's page size")
    func pagesResults() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        let (store, _) = await Self.makeStore(repo)
        await Self.search(store, HistorySearchQuery(author: "ana@"))
        #expect(store.search.results.map(\.subject) == ["commit 11", "commit 10", "commit 8"])
        #expect(store.search.hasMore)
        // The first result is selected, like the log's first page.
        #expect(store.selectedCommitId == store.search.results.first?.id)

        // Only the last row asks for more.
        store.search.loadMoreIfNeeded(currentItem: store.search.results[0])
        #expect(!store.search.isLoadingMore)
        while store.search.hasMore, let last = store.search.results.last {
            store.search.loadMoreIfNeeded(currentItem: last)
            await store.search.waitForSearch()
        }
        #expect(store.search.results.map(\.subject)
                == ["commit 11", "commit 10", "commit 8", "commit 7", "commit 5", "commit 4", "commit 2", "commit 1 first"])
        #expect(!store.search.isLoadingMore)
    }

    @Test("A new query supersedes the one in flight")
    func newQuerySupersedes() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        let (store, _) = await Self.makeStore(repo)
        store.search.draft = HistorySearchQuery(author: "ana@")
        store.search.run()
        store.search.draft = HistorySearchQuery(author: "bo@")
        store.search.run()
        await store.search.waitForSearch()
        // Give the first search's git time to come back: it must not land.
        try await Task.sleep(for: .milliseconds(300))
        #expect(store.search.activeQuery == HistorySearchQuery(author: "bo@"))
        #expect(store.search.results.map(\.subject) == ["commit 12", "commit 9", "commit 6"])
        #expect(!store.search.isSearching)
    }

    @Test("Stop ends the fetch in flight and keeps the chips")
    func stop() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        let (store, _) = await Self.makeStore(repo)
        store.search.show(.message)
        store.search.draft = HistorySearchQuery(message: "commit")
        store.search.run()
        #expect(store.search.isSearching)
        store.search.stop()
        await store.search.waitForSearch()
        try await Task.sleep(for: .milliseconds(300))
        #expect(!store.search.isSearching)
        #expect(store.search.isStopped)
        #expect(store.search.results.isEmpty)
        #expect(store.search.isActive)
        #expect(store.search.visibleFields == [.message])
    }

    @Test("Clearing the search restores the graph's selection; an empty query clears it too")
    func clearRestoresSelection() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        let (store, _) = await Self.makeStore(repo)
        let before = store.commits[1].id
        store.selectedCommitId = before

        store.search.show(.author)
        await Self.search(store, HistorySearchQuery(author: "bo@"))
        #expect(store.search.isActive)
        #expect(store.selectedCommitId == store.search.results.first?.id)
        // Another query keeps the selection to restore from before the first one.
        await Self.search(store, HistorySearchQuery(message: "commit 3"))
        store.selectedCommitId = store.search.results.last?.id

        store.search.clear()
        #expect(!store.search.isActive)
        #expect(store.search.results.isEmpty && store.search.resultsById.isEmpty)
        #expect(store.search.visibleFields.isEmpty)
        #expect(store.search.draft == HistorySearchQuery())
        #expect(store.selectedCommitId == before)

        // Removing the last criterion ends the search the same way.
        store.search.show(.message)
        await Self.search(store, HistorySearchQuery(message: "commit 2"))
        #expect(store.search.isActive)
        store.search.remove(.message)
        #expect(!store.search.isActive)
        #expect(store.selectedCommitId == before)
    }

    @Test("Removing one of two criteria runs the search again without it")
    func removeCriterionReruns() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        let (store, _) = await Self.makeStore(repo)
        store.search.show(.author)
        store.search.show(.message)
        await Self.search(store, HistorySearchQuery(message: "commit 1", author: "bo@"))
        #expect(store.search.results.map(\.subject) == ["commit 12"])
        store.search.remove(.author)
        await store.search.waitForSearch()
        #expect(store.search.activeQuery == HistorySearchQuery(message: "commit 1"))
        #expect(store.search.results.map(\.subject) == ["commit 12", "commit 11", "commit 10"])
        #expect(store.search.hasMore)
        #expect(store.search.visibleFields == [.message])
    }

    @Test("showCommits(byAuthor:) sets the Author criterion and runs the search")
    func showCommitsByAuthor() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        let (store, _) = await Self.makeStore(repo, pageSize: 50)
        store.search.showCommits(byAuthor: "bo@example.com")
        await store.search.waitForSearch()
        #expect(store.search.visibleFields == [.author])
        #expect(store.search.activeQuery == HistorySearchQuery(author: "bo@example.com"))
        #expect(store.search.results.map(\.subject) == ["commit 12", "commit 9", "commit 6", "commit 3"])
    }

    @Test("Jumping to a result below the loaded pages loads them, selects it and ends the search")
    func jumpLoadsPages() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        let (store, _) = await Self.makeStore(repo)
        await Self.search(store, HistorySearchQuery(message: "commit 5"))
        let target = try #require(store.search.results.first)
        #expect(target.subject == "commit 5")
        #expect(store.commitsById[target.id] == nil)

        #expect(await store.search.jumpToGraph(target.id))
        #expect(!store.search.isActive)
        #expect(store.selectedCommitId == target.id)
        // Whole pages down to the one holding commit 5 (rows 7…9 of 12), as if scrolled to.
        #expect(store.commits.map(\.subject) == (4...12).reversed().map { "commit \($0)" })
        #expect(store.graphPageEnds == [3, 6, 9])
        #expect(store.loadedRawCount == 9)
        #expect(store.graphLayouts.count == store.commits.count)
        #expect(store.hasMore)

        // Pagination goes on from there.
        await store.loadMoreIfNeeded(currentItem: try #require(store.commits.last))
        #expect(store.commits.last?.subject == "commit 1 first")
        #expect(store.graphPageEnds == [3, 6, 9, 12])
    }

    @Test("Jumping to a loaded result only selects it")
    func jumpToLoaded() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        let (store, _) = await Self.makeStore(repo)
        await Self.search(store, HistorySearchQuery(message: "commit 11"))
        let target = try #require(store.search.results.first)
        #expect(await store.search.jumpToGraph(target.id))
        #expect(store.selectedCommitId == target.id)
        #expect(store.loadedRawCount == 3)
    }

    @Test("Stashes and their internal commits are not searched")
    func stashesExcluded() async throws {
        let repo = try await Self.makeRepo(count: 3)
        defer { repo.remove() }
        try await repo.perform { repo in
            try repo.write("dirty\n", to: "file.txt")
            try repo.write("new\n", to: "untracked.txt")
            try repo.git("stash", "push", "-q", "-u", "-m", "commit stash")
        }
        let (store, refs) = await Self.makeStore(repo, pageSize: 50)
        #expect(!refs.stashes.isEmpty)
        #expect(!store.searchScope().stashShas.isEmpty)
        await Self.search(store, HistorySearchQuery(message: "commit"))
        #expect(store.search.results.map(\.subject) == ["commit 3", "commit 2", "commit 1 first"])
    }

    @Test("An invalid regex shows git's error")
    func invalidRegex() async throws {
        let repo = try await Self.makeRepo(count: 2)
        defer { repo.remove() }
        let (store, _) = await Self.makeStore(repo)
        await Self.search(store, HistorySearchQuery(content: "(", contentIsRegex: true))
        #expect(store.search.error != nil)
        #expect(store.search.results.isEmpty)
        #expect(!store.search.isSearching)
    }

    // MARK: Path completion

    @Test("Tracked paths include every folder above them")
    func pathsWithFolders() {
        #expect(HistorySearchStore.pathsWithFolders(["a/b/c.swift", "a/d.swift", "e.md"])
                == ["a/", "a/b/", "a/b/c.swift", "a/d.swift", "e.md"])
        #expect(HistorySearchStore.pathsWithFolders([]).isEmpty)
    }

    @Test("Suggestions: paths that start with the text first, shorter first, ignoring case")
    func pathSuggestions() {
        let paths = ["Sources/", "Sources/Graph.swift", "Tests/GraphTests.swift", "Sources/Graph/", "graph.md", "README.md"]
        #expect(HistorySearchStore.pathSuggestions(for: "graph", in: paths)
                == ["graph.md", "Sources/Graph/", "Sources/Graph.swift", "Tests/GraphTests.swift"])
        #expect(HistorySearchStore.pathSuggestions(for: "Sources/", in: paths)
                == ["Sources/Graph/", "Sources/Graph.swift"])
        #expect(HistorySearchStore.pathSuggestions(for: "  ", in: paths).isEmpty)
        #expect(HistorySearchStore.pathSuggestions(for: "s", in: paths, limit: 2).count == 2)
    }

    @Test("loadTrackedPaths reads the index")
    func loadTrackedPaths() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("files", files: ["Sources/App/main.swift": "1", "README.md": "2"])
        }
        defer { repo.remove() }
        let store = HistorySearchStore(cli: repo.cli)
        await store.loadTrackedPaths()
        #expect(store.trackedPaths == ["README.md", "Sources/", "Sources/App/", "Sources/App/main.swift"])
    }
}
