import Foundation
import Testing
@testable import gitForge

/// Live FSEvents behaviour against a real repository. The previous
/// `DispatchSource` watchers were bound to inodes: `.git/HEAD` went dark after
/// the first checkout (git replaces it via rename) and nested refs such as
/// `refs/heads/feature/x` never fired at all.
@Suite("RepositoryWatcher — live events", .serialized)
@MainActor
struct RepositoryWatcherLiveTests {

    private final class Counter {
        var value = 0
    }

    /// Waits until `counter` exceeds `baseline`, or fails after `timeout`.
    private func expectRefresh(after baseline: Int, _ counter: Counter, _ label: String,
                               timeout: Duration = .seconds(5)) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while counter.value <= baseline, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(counter.value > baseline, "no refresh after \(label)")
        // Let the debounce window close so the next step starts clean.
        try await Task.sleep(for: .milliseconds(400))
    }

    @Test("Repeated checkouts, nested-branch commits and worktree edits all refresh")
    func liveEvents() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("init", files: ["a.txt": "a\n"])
            try repo.git("branch", "other")
            try repo.git("branch", "feature/x")
        }
        defer { repo.remove() }

        let counter = Counter()
        let watcher = RepositoryWatcher(repository: repo.url) { counter.value += 1 }
        defer { _ = watcher }
        // FSEvents needs a moment to arm before the first change.
        try await Task.sleep(for: .milliseconds(300))

        for (index, branch) in ["other", "main", "other"].enumerated() {
            let baseline = counter.value
            try await repo.gitAsync("checkout", "-q", branch)
            try await expectRefresh(after: baseline, counter, "checkout #\(index + 1) (\(branch))")
        }

        var baseline = counter.value
        try await repo.gitAsync("checkout", "-q", "feature/x")
        try await expectRefresh(after: baseline, counter, "checkout feature/x")

        baseline = counter.value
        try await repo.gitAsync("commit", "-q", "--allow-empty", "-m", "nested")
        try await expectRefresh(after: baseline, counter, "commit on feature/x")

        baseline = counter.value
        try await repo.externalWriteAsync("edited\n", to: "a.txt")
        try await expectRefresh(after: baseline, counter, "worktree edit")
    }
}
