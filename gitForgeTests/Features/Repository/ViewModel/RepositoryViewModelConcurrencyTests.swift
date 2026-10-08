import Foundation
import Testing
@testable import gitForge

/// Lifecycle and interleaving regressions found in audit A03.
@Suite("RepositoryViewModel — concurrency & lifecycle", .serialized)
@MainActor
struct RepositoryViewModelConcurrencyTests {

    private func makeRepo(commits: Int = 3) async throws -> GitTestRepo {
        try await GitTestRepo.make { repo in
            for index in 0..<commits {
                try repo.commit("c\(index)", files: ["f.txt": "\(index)\n"])
            }
        }
    }

    @Test("A reload landing mid-pagination doesn't leave isLoadingMore stuck")
    func paginationFlagSurvivesReload() async throws {
        let repo = try await makeRepo()
        defer { repo.remove() }
        let vm = RepositoryViewModel(repository: Repository(url: repo.url))
        await vm.loadInitial()
        let last = try #require(vm.commits.last)
        vm.hasMore = true // force the pagination path on a short history

        async let page: Void = vm.loadMoreIfNeeded(currentItem: last)
        async let reload: Void = vm.reloadLog()
        _ = await (page, reload)

        #expect(!vm.isLoadingMore)
        #expect(!vm.isPaginating)
        #expect(vm.commits.count == 3)
    }

    @Test("A reload landing mid-loadInitial doesn't leave isLoadingInitial stuck")
    func initialFlagSurvivesReload() async throws {
        let repo = try await makeRepo()
        defer { repo.remove() }
        let vm = RepositoryViewModel(repository: Repository(url: repo.url))

        async let initial: Void = vm.loadInitial()
        async let reload: Void = vm.reloadLog()
        _ = await (initial, reload)

        #expect(!vm.isLoadingInitial)
        // And a later loadInitial (empty log) still runs.
        vm.commits = []
        await vm.loadInitial()
        #expect(vm.commits.count == 3)
    }

    @Test("Tracked tasks deregister themselves when they finish")
    func trackedTasksDeregister() async throws {
        let vm = RepositoryViewModel(repository: Repository(url: URL(fileURLWithPath: "/var/empty")))
        for _ in 0..<5 { vm.track { } }
        #expect(vm.ownedTasks.count == 5)
        for _ in 0..<20 where !vm.ownedTasks.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(vm.ownedTasks.isEmpty)
    }

    @Test("Pull holds isMutating so local mutations can't race it")
    func pullIsAMutation() async throws {
        let repo = try await makeRepo(commits: 1)
        defer { repo.remove() }
        let vm = RepositoryViewModel(repository: Repository(url: repo.url))
        vm.isMutating = true
        await vm.pull()
        // Refused up front: no remote op started, no failure surfaced.
        #expect(vm.remoteOperation == nil)
        #expect(vm.remoteFailure == nil)
    }
}

@Suite("RepositoryCatalog — open ordering", .serialized)
@MainActor
struct RepositoryCatalogOpenTests {

    @Test("The most recent open wins even if an earlier one finishes later")
    func lastOpenWins() async throws {
        let first = try await GitTestRepo.make()
        let second = try await GitTestRepo.make()
        let storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitForge-catalog-\(UUID().uuidString)")
        let suiteName = "gitForge-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            first.remove(); second.remove()
            try? FileManager.default.removeItem(at: storeDir)
            defaults.removePersistentDomain(forName: suiteName)
        }
        let catalog = RepositoryCatalog(store: RepositoryStore(directory: storeDir), defaults: defaults)

        // Start the first open and let it run to its first suspension (it
        // has bumped the generation by then), *then* open the second — the
        // order a user's two clicks produce. Two `async let`s don't
        // guarantee which child starts first.
        let openFirst = Task { try await catalog.open(at: first.url) }
        await Task.yield()
        _ = try await catalog.open(at: second.url)
        _ = try await openFirst.value

        let expected = second.url.standardizedFileURL.canonicalFileSystemPath
        #expect(catalog.activeRepository?.url.canonicalFileSystemPath == expected)
        #expect(catalog.activeViewModel?.repository.url.canonicalFileSystemPath == expected)
    }
}
