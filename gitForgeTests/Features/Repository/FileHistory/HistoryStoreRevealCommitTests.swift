import Foundation
import Testing
@testable import gitForge

/// "Open in History" from File history: the commit may be pages below
/// what History has loaded.
@Suite("History reveal commit", .serialized)
@MainActor
struct HistoryStoreRevealCommitTests {

    /// c0 … c9 on main.
    private static func repo() async throws -> GitTestRepo {
        try await GitTestRepo.make { repo in
            for n in 0..<10 { try repo.commit("c\(n)", files: ["f.txt": "\(n)\n"]) }
        }
    }

    @Test("A commit below the loaded pages is paged in and selected")
    func pagesIn() async throws {
        let repo = try await Self.repo()
        defer { repo.remove() }
        let vm = RepositoryViewModel(repository: Repository(url: repo.url))
        vm.history.pageSize = { 3 }
        await vm.loadRefs()
        await vm.history.loadInitial()
        #expect(vm.history.commits.count == 3)
        let c1 = try await repo.gitAsync("rev-parse", "HEAD~8").trimmingCharacters(in: .whitespacesAndNewlines)

        let found = await vm.history.revealCommit(c1)

        #expect(found)
        #expect(vm.history.selectedCommitId == c1)
        #expect(vm.history.commits.contains { $0.sha == c1 })
        #expect(vm.history.graphLayouts.count == vm.history.commits.count)
    }

    @Test("A commit already loaded is selected without loading more")
    func alreadyLoaded() async throws {
        let repo = try await Self.repo()
        defer { repo.remove() }
        let vm = RepositoryViewModel(repository: Repository(url: repo.url))
        vm.history.pageSize = { 3 }
        await vm.loadRefs()
        await vm.history.loadInitial()
        let second = vm.history.commits[1].sha

        #expect(await vm.history.revealCommit(second))
        #expect(vm.history.selectedCommitId == second)
        #expect(vm.history.commits.count == 3)
    }

    @Test("A commit that isn't in History leaves the selection alone")
    func notInHistory() async throws {
        let repo = try await Self.repo()
        defer { repo.remove() }
        let vm = RepositoryViewModel(repository: Repository(url: repo.url))
        vm.history.pageSize = { 3 }
        await vm.loadRefs()
        await vm.history.loadInitial()
        let selected = vm.history.selectedCommitId

        #expect(await !vm.history.revealCommit(String(repeating: "f", count: 40)))
        #expect(vm.history.selectedCommitId == selected)
        // A failed reveal changes nothing: the pages it walked aren't published.
        #expect(vm.history.commits.count == 3)
    }
}
