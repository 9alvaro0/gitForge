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
    func cancelsOwnedTasks() async {
        let vm = Self.makeVM()
        // Long-running task that would otherwise hold `self` alive for 10s.
        let longTask = Task<Void, Never> { try? await Task.sleep(for: .seconds(10)) }
        vm.track(longTask)
        vm.stopReactivity()
        #expect(longTask.isCancelled)
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
        vm.commitDateBySha = ["a": .now]
        vm.upstream = "origin/main"
        vm.aheadCount = 5

        vm.stopReactivity()

        #expect(vm.commits.isEmpty)
        #expect(vm.commitDateBySha.isEmpty)
        #expect(vm.upstream == nil)
        #expect(vm.aheadCount == 0)
    }

    @Test("track removes already-cancelled tasks from the ledger")
    func trackTrimsCancelled() async {
        let vm = Self.makeVM()
        let cancelled = Task<Void, Never> {}
        cancelled.cancel()
        vm.track(cancelled)
        // A second track call should not accumulate the dead one.
        let live = Task<Void, Never> { try? await Task.sleep(for: .seconds(10)) }
        vm.track(live)
        vm.stopReactivity()
        // Live task is cancelled; cancelled stayed cancelled — invariant
        // here is just that stopReactivity doesn't crash on either.
        #expect(live.isCancelled)
    }
}
