import Foundation
import Testing
@testable import gitForge

/// Spec §7: the v3 engine must stay within 1.5x the legacy engine on a large
/// synthetic history. `.serialized` only orders this suite's own tests (the
/// fixture test cannot overlap the timed run); other suites still run in
/// parallel, so the 1.5x bound is generous enough to absorb the noise.
@Suite("CommitGraphEngine performance", .serialized)
struct CommitGraphPerformanceTests {
    @Test("50,000 commits lay out within 1.5× the legacy engine")
    func fiftyThousand() {
        let (commits, refs) = GraphFixture.synthetic(commits: 50_000, branches: 12, seed: 7)
        let input = GraphInput(commits: commits, headSha: commits.first?.sha, refs: refs)
        let refsBySha = Dictionary(grouping: refs, by: \.targetSha)
        func median(_ body: () -> Void) -> Duration {
            (0..<3).map { _ in ContinuousClock().measure(body) }.sorted()[1]
        }
        let legacy = median { _ = LegacyGraphLayoutEngine.layouts(for: commits, refsBySha: refsBySha) }
        let current = median { _ = CommitGraphEngine.layout(input) }
        #expect(current <= legacy * 1.5, "v3 \(current) vs legacy \(legacy)")
    }

    @Test("The synthetic history is reproducible, topologically ordered and complete")
    func syntheticFixture() {
        let first = GraphFixture.synthetic(commits: 3_000, branches: 12, seed: 7)
        let second = GraphFixture.synthetic(commits: 3_000, branches: 12, seed: 7)
        #expect(first.commits == second.commits)
        #expect(first.refs == second.refs)
        #expect(first.commits != GraphFixture.synthetic(commits: 3_000, branches: 12, seed: 8).commits)

        let (commits, refs) = first
        #expect(commits.count == 3_000)
        // Shas are c<row>, parents always sit on later rows, and the last row is the root.
        for (row, commit) in commits.enumerated() {
            #expect(commit.sha == "c\(row)")
            #expect(commit.parentShas.allSatisfy { Int($0.dropFirst())! > row })
        }
        #expect(commits.last?.parentShas == [])
        #expect(commits.contains { $0.parentShas.count == 2 })

        let shas = Set(commits.map(\.sha))
        #expect(refs.allSatisfy { shas.contains($0.targetSha) })
        #expect(refs.filter(\.isHead).map(\.name) == ["main"])
        #expect(refs.count <= 13)
    }
}
