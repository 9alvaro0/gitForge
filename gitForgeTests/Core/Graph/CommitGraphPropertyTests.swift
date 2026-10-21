import Foundation
import Testing
@testable import gitForge

/// The commit graph engine on random histories: merges (octopus included),
/// several roots, stashes, local branches with and without an upstream,
/// remote-only refs, detached HEAD, truncated logs and two pages. The seeds are
/// fixed, so a failure always reproduces, and it reports the history in the
/// `GraphFixture.commits` format.
@Suite("CommitGraphProperties")
struct CommitGraphPropertyTests {
    private static let seeds: ClosedRange<UInt64> = 1...2_000
    /// Failing histories reported in full; the rest are only counted.
    private static let reportedFailures = 3

    @Test("Random histories keep the layout invariants")
    func invariants() {
        var failures = 0
        for seed in Self.seeds {
            let history = RandomHistory(seed: seed)
            let violations = GraphInvariants.violations(CommitGraphEngine.layout(history.input), history.input)
            guard !violations.isEmpty else { continue }
            failures += 1
            if failures <= Self.reportedFailures {
                Issue.record(Comment(rawValue: "\(history)\n" + violations.joined(separator: "\n")))
            }
        }
        #expect(failures == 0)
    }

    @Test("Loading the second page of a random history only adds rows below")
    func paging() {
        var checked = 0
        var failures = 0
        for seed in Self.seeds {
            let history = RandomHistory(seed: seed)
            guard Self.isPagingCase(history.input) else { continue }
            checked += 1
            if let change = Self.pagingChange(history.input) {
                failures += 1
                if failures <= Self.reportedFailures {
                    Issue.record(Comment(rawValue: "\(history)\n\(change)"))
                }
            }
        }
        #expect(failures == 0)
        #expect(checked > 500)
    }

    /// Histories that once changed colours on page 1 when page 2 loaded: a stretch
    /// near the end of page 1 saw a page-2 neighbour whose owner already had a
    /// colour (seed 11407 through HEAD's line, seed 29410 through a remote that
    /// copies its local branch's colour).
    @Test("Page-1 colours ignore page-2 neighbours", arguments: [UInt64(11_407), 29_410])
    func pagingRegression(seed: UInt64) {
        let history = RandomHistory(seed: seed)
        #expect(Self.isPagingCase(history.input))
        if let change = Self.pagingChange(history.input) {
            Issue.record(Comment(rawValue: "\(history)\n\(change)"))
        }
    }

    /// Two pages, and not the shape deferred to G3 (`startsOnLaterPage`).
    private static func isPagingCase(_ input: GraphInput) -> Bool {
        input.pageEnds.count == 2 && !startsOnLaterPage(input, firstPageEnd: input.pageEnds[0])
    }

    /// What loading the second page changed in the first, or nil when it only added
    /// rows below. The last row of the first page may change below its node: a
    /// line that ran past the end now forks, or a track now enters its parent.
    private static func pagingChange(_ full: GraphInput) -> String? {
        let split = full.pageEnds[0]
        var firstPage = full
        firstPage.commits = Array(full.commits.prefix(split))
        firstPage.pageEnds = [split]
        let before = CommitGraphEngine.layout(firstPage).rows
        let after = CommitGraphEngine.layout(full).rows
        let last = split - 1
        for row in 0..<last where after[row] != before[row] {
            return "Row \(row) changed when page 2 loaded:\nbefore \(before[row])\nafter  \(after[row])"
        }
        if after[last].node != before[last].node || after[last].stepsAbove != before[last].stepsAbove {
            return "Row \(last), the last of page 1, changed above its centre when page 2 loaded:\n"
                + "before \(before[last])\nafter  \(after[last])"
        }
        return nil
    }

    /// A local branch whose upstream's tip is on the first page while its own tip
    /// loads on the second. It has no line until its tip loads (Task 1 starts a
    /// branch only from a loaded tip), so page 2 can move what page 1 drew.
    /// Deferred to G3: in G1 the default scope loads no remote-only commits, so
    /// this needs an upstream tip that another local branch reaches.
    private static func startsOnLaterPage(_ input: GraphInput, firstPageEnd: Int) -> Bool {
        let rowOf = input.rowIndex()
        var remoteRows: [String: Int] = [:]
        for ref in input.refs where ref.isRemoteBranch {
            remoteRows[ref.name] = rowOf[ref.targetSha]
        }
        return input.refs.contains { ref in
            guard ref.isLocalBranch, let upstream = ref.upstream,
                  let upstreamRow = remoteRows[upstream], upstreamRow < firstPageEnd,
                  let localRow = rowOf[ref.targetSha] else { return false }
            return localRow >= firstPageEnd
        }
    }
}

// MARK: - Random histories

/// A seeded history of 3 to 14 commits, rows `c0` (newest) to `cN` (oldest).
private struct RandomHistory: CustomStringConvertible {
    let seed: UInt64
    let input: GraphInput
    let description: String

    init(seed: UInt64) {
        self.seed = seed
        var random = SplitMix64(seed: seed)
        let total = random.int(in: 3...14)

        // Parents always sit on later rows, so the rows are topologically ordered.
        var parents: [[Int]] = Array(repeating: [], count: total)
        for row in 0..<total {
            let later = Array((row + 1)..<total)
            if later.isEmpty || random.chance(0.08) { continue }
            parents[row].append(later[min(later.count - 1, random.int(in: 0...3))])
            if random.chance(0.35) {
                for _ in 0..<(random.chance(0.2) ? 2 : 1) {
                    let extra = later[random.int(in: 0...(later.count - 1))]
                    if !parents[row].contains(extra) { parents[row].append(extra) }
                }
            }
        }

        // Stashes are commits nothing descends from; some keep an index parent that is never loaded.
        var hasChild = Array(repeating: false, count: total)
        for list in parents { for parent in list { hasChild[parent] = true } }
        var stashRows: Set<Int> = []
        for row in 0..<total where !hasChild[row] && !parents[row].isEmpty && random.chance(0.2) {
            stashRows.insert(row)
        }
        func anyCommitRow() -> Int {
            var row = random.int(in: 0...(total - 1))
            while stashRows.contains(row) { row = (row + 1) % total }
            return row
        }

        // Half the histories are truncated, and some of those are split into two pages.
        let loaded = random.chance(0.5) ? total : random.int(in: 1...total)
        var lines: [String] = []
        for row in 0..<loaded {
            var words = ["c\(row)"] + parents[row].map { "c\($0)" }
            if stashRows.contains(row), random.chance(0.5) { words.append("index\(row)") }
            lines.append(words.joined(separator: " "))
        }
        var pageEnds: [Int] = []
        if loaded > 2, random.chance(0.5) {
            pageEnds = [random.int(in: 1...(loaded - 1)), loaded]
        }

        // Local branches, some tracking an upstream with real ahead/behind counts.
        func reachable(from start: Int) -> Set<Int> {
            var seen: Set<Int> = [start]
            var pending = [start]
            while let row = pending.popLast() {
                for parent in parents[row] where seen.insert(parent).inserted { pending.append(parent) }
            }
            return seen
        }
        let names = ["main", "develop", "release/1", "hotfix/x", "feature/a", "feature/b", "feature/c"]
        var refs: [GitRef] = []
        var used: Set<String> = []
        for _ in 0..<random.int(in: 0...5) {
            let name = names[random.int(in: 0...(names.count - 1))]
            guard used.insert(name).inserted else { continue }
            let row = anyCommitRow()
            if random.chance(0.3) {
                let upstreamRow = anyCommitRow()
                let local = reachable(from: row)
                let upstream = reachable(from: upstreamRow)
                refs.append(GraphFixture.local(name, "c\(row)", upstream: "origin/\(name)",
                                               ahead: local.subtracting(upstream).count,
                                               behind: upstream.subtracting(local).count))
                refs.append(GraphFixture.remote("origin/\(name)", "c\(upstreamRow)"))
            } else {
                refs.append(GraphFixture.local(name, "c\(row)"))
            }
        }
        if random.chance(0.2) {
            refs.append(GraphFixture.remote("origin/other", "c\(anyCommitRow())"))
        }

        // HEAD on a local branch most of the time, otherwise detached.
        let headSha: String
        let locals = refs.indices.filter { refs[$0].isLocalBranch }
        if !locals.isEmpty, random.chance(0.8) {
            let index = locals[random.int(in: 0...(locals.count - 1))]
            let ref = refs[index]
            refs[index] = GitRef(name: ref.name, kind: ref.kind, targetSha: ref.targetSha, isHead: true,
                                 upstream: ref.upstream, ahead: ref.ahead, behind: ref.behind)
            headSha = ref.targetSha
        } else {
            headSha = "c\(anyCommitRow())"
        }

        let stashShas = Set(stashRows.map { "c\($0)" })
        input = GraphInput(commits: GraphFixture.commits(lines.joined(separator: "\n")), pageEnds: pageEnds,
                           headSha: headSha, refs: refs, stashShas: stashShas, paletteSize: 4)
        let refText = refs.map { ref in
            let upstream = ref.upstream.map { " -> \($0) ahead \(ref.ahead ?? 0) behind \(ref.behind ?? 0)" } ?? ""
            return "\(ref.name)@\(ref.targetSha)\(ref.isHead ? " (HEAD)" : "")\(upstream)"
        }
        description = """
            seed \(seed)
            \(lines.joined(separator: "\n"))
            pageEnds \(pageEnds), headSha \(headSha), stashes \(stashShas.sorted())
            refs: \(refText.joined(separator: ", "))
            """
    }
}
