import Foundation
import Testing
@testable import gitForge

@Suite("RepositoryViewModel — stopReactivity teardown", .serialized)
@MainActor
struct RepositoryViewModelLifecycleTests {

    private static func makeVM() -> RepositoryViewModel {
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        return RepositoryViewModel(repository: Repository(url: url))
    }

    @Test("stopReactivity cancels tracked owned tasks")
    func cancelsOwnedTasks() async throws {
        let vm = Self.makeVM()
        let observed = CancellationProbe()
        // Long-running work that would otherwise hold `self` alive for 10s.
        vm.track {
            try? await Task.sleep(for: .seconds(10))
            observed.wasCancelled = Task.isCancelled
        }
        vm.stopReactivity()
        #expect(vm.ownedTasks.isEmpty)
        for _ in 0..<50 where observed.wasCancelled == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(observed.wasCancelled == true)
    }

    @Test("stopReactivity drops the heavy in-memory caches")
    func purgesCaches() async {
        let vm = Self.makeVM()
        // Seed the publicly-settable caches with payload to prove they're
        // cleared. (commitsById is private(set) — its purge is exercised
        // indirectly through `commits` going empty.)
        vm.commits = [
            Commit(sha: "a", parentShas: [], authorName: "x", authorEmail: "x@x", authorDate: .now, subject: "one")
        ]
        vm.upstream = "origin/main"
        vm.aheadCount = 5

        vm.stopReactivity()

        #expect(vm.commits.isEmpty)
        #expect(vm.upstream == nil)
        #expect(vm.aheadCount == 0)
    }
}

@MainActor
private final class CancellationProbe {
    var wasCancelled: Bool?
}
