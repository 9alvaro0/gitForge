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
        let legacy = median { _ = LegacyGraphLayoutEngine.layouts(for: commits, refsBySha: refsBySha) }
        let current = median { _ = CommitGraphEngine.layout(input) }
        #expect(current <= legacy * 1.5, "v3 \(current) vs legacy \(legacy)")
    }

    @Test("50,000 commits with remotes, stashes and 200-commit pages lay out within 1.5× the legacy engine")
    func fiftyThousandAfterFetch() {
        let (commits, refs, stashShas) = GraphFixture.syntheticAfterFetch(commits: 50_000, branches: 12,
                                                                          seed: 7, stashes: 3)
        let pageEnds = Array(stride(from: 200, to: commits.count, by: 200)) + [commits.count]
        let input = GraphInput(commits: commits, pageEnds: pageEnds, headSha: refs.first(where: \.isHead)?.targetSha,
                               refs: refs, stashShas: stashShas)
        let refsBySha = Dictionary(grouping: refs, by: \.targetSha)
        let legacy = median { _ = LegacyGraphLayoutEngine.layouts(for: commits, refsBySha: refsBySha) }
        let current = median { _ = CommitGraphEngine.layout(input) }
        #expect(current <= legacy * 1.5, "v3 \(current) vs legacy \(legacy)")
    }

    /// Median of 3 runs, so one slow run (other suites share the machine) doesn't decide.
    private func median(_ body: () -> Void) -> Duration {
        (0..<3).map { _ in ContinuousClock().measure(body) }.sorted()[1]
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

    @Test("The synthetic history after a fetch: real counts, every server-only commit a ghost")
    func afterFetchFixture() {
        let (commits, refs, stashShas) = GraphFixture.syntheticAfterFetch(commits: 3_000, branches: 12,
                                                                          seed: 7, stashes: 3)

        // The log stays topological: every loaded parent sits on a later row, and no sha repeats.
        let rowOf = Dictionary(commits.enumerated().map { ($1.sha, $0) }, uniquingKeysWith: { first, _ in first })
        #expect(rowOf.count == commits.count)
        for (row, commit) in commits.enumerated() {
            #expect(commit.parentShas.compactMap { rowOf[$0] }.allSatisfy { $0 > row })
        }

        // Ahead/behind of every local ref equal the commits reachable only from one side.
        let locals = refs.filter(\.isLocalBranch)
        let remotes = Dictionary(uniqueKeysWithValues: refs.filter(\.isRemoteBranch).map { ($0.name, $0) })
        #expect(locals.count > 3)
        for local in locals {
            guard let upstream = local.upstream, let remote = remotes[upstream] else {
                Issue.record("\(local.name) has no upstream ref in the fixture")
                continue
            }
            let own = CommitAncestry.reachable(from: local.targetSha, in: commits)
            let theirs = CommitAncestry.reachable(from: remote.targetSha, in: commits)
            #expect(local.ahead == own.subtracting(theirs).count, "\(local.name) ahead")
            #expect(local.behind == theirs.subtracting(own).count, "\(local.name) behind")
        }
        let shapes = Set(locals.map { "\($0.ahead ?? -1)/\($0.behind ?? -1)" })
        #expect(shapes == ["0/5", "0/3", "1/2", "0/0"], "main behind 5, then the three kinds of feature")

        // The ghost rows are exactly the server-only commits, which no local ref reaches.
        let serverRows = commits.indices.filter { commits[$0].sha.hasPrefix("s") }
        #expect(serverRows.count == locals.compactMap(\.behind).reduce(0, +))
        #expect(commits.count == 3_000 + serverRows.count + 3)
        let input = GraphInput(commits: commits, headSha: refs.first(where: \.isHead)?.targetSha,
                               refs: refs, stashShas: stashShas)
        let layout = CommitGraphEngine.layout(input)
        #expect(layout.rows.indices.filter { layout.rows[$0].node.isGhost } == serverRows)

        // Three stashes, each on a loaded commit with an index parent that isn't loaded.
        #expect(stashShas.count == 3)
        for sha in stashShas {
            let parents = rowOf[sha].map { commits[$0].parentShas } ?? []
            #expect(parents.count == 2 && rowOf[parents[0]] != nil && rowOf[parents[1]] == nil, "stash \(sha)")
        }
        #expect(layout.rows.filter { $0.node.kind == .stash }.count == 3)
    }
}
