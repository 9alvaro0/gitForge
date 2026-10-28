import Foundation
import Testing
@testable import gitForge

/// Counts how many reads run at once.
private actor Gauge {
    private(set) var current = 0
    private(set) var peak = 0
    func enter() { current += 1; peak = max(peak, current) }
    func leave() { current -= 1 }
}

@Suite("RecentsModel", .serialized)
@MainActor
struct RecentsModelTests {

    @Test("A clean repo is ready and Clean; a missing folder is Missing")
    func realRepos() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("first", files: ["a.txt": "a\n"])
        }
        defer { repo.remove() }
        let gone = URL(fileURLWithPath: "/tmp/gitforge-missing-\(UUID().uuidString)")
        let model = RecentsModel()
        await model.load([Repository(url: repo.url), Repository(url: gone)])
        guard case .ready(let summary) = model.states[repo.url] else {
            Issue.record("expected ready, got \(String(describing: model.states[repo.url]))")
            return
        }
        #expect(summary.label == "Clean")
        #expect(model.states[gone] == .missing)
    }

    @Test("At most four repos are read at once")
    func concurrency() async {
        let gauge = Gauge()
        let model = RecentsModel(read: { _ in
            await gauge.enter()
            try? await Task.sleep(for: .milliseconds(30))
            await gauge.leave()
            return .ready(RecentRepoSummary(branch: "main", changed: 0, ahead: 0, behind: 0))
        })
        let repos = (0..<6).map { Repository(url: URL(fileURLWithPath: "/tmp/r\($0)")) }
        await model.load(repos)
        #expect(await gauge.peak == 4)
        #expect(model.states.count == 6)
    }

    @Test("A load cancelled half-way leaves the unread repos unknown, not Missing, so the next load reads them")
    func cancelled() async {
        let model = RecentsModel(read: { _ in
            try? await Task.sleep(for: .seconds(5))
            if Task.isCancelled { return nil }
            return .ready(RecentRepoSummary(branch: "main", changed: 0, ahead: 0, behind: 0))
        })
        let repos = (0..<6).map { Repository(url: URL(fileURLWithPath: "/tmp/c\($0)")) }
        let loading = Task { await model.load(repos) }
        try? await Task.sleep(for: .milliseconds(50))
        loading.cancel()
        await loading.value
        #expect(model.states.isEmpty)
    }
}
