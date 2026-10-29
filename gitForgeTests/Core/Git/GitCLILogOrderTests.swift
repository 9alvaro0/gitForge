import Foundation
import Testing
@testable import gitForge

/// The order `GitCLI.log` loads a gitflow history in. Every release merge on main has
/// its second parent on develop's side, and git can't emit that parent before its
/// children on develop. A local branch forked from develop and not merged yet holds
/// develop back until git gets to that branch's tip. `--topo-order` kept going down
/// main's first parents meanwhile, so it emitted every release merge before any of
/// develop, and each one kept a column open down to its release, far below. By commit
/// date the release sits right below its merge.
@Suite("GitCLI.log — order of a gitflow history")
struct GitCLILogOrderTests {

    enum ReleaseShape: String, CaseIterable, CustomTestStringConvertible {
        /// Each release gets a commit of its own and is merged into main and back into develop.
        case mergedBack
        /// Each release is develop's tip at the time, merged into main; develop moves on.
        case cutFromDevelop

        var testDescription: String { rawValue }
    }

    private static let releases = 8

    /// main and develop with `releases` releases, each commit an hour after the last,
    /// tagged on main and ending with main checked out. Before the last release,
    /// `feature/wip` forks from develop with a commit of its own and stays unmerged.
    private static func makeGitflow(_ shape: ReleaseShape) async throws -> GitTestRepo {
        try await GitTestRepo.make { repo in
            var hour = 0
            func dated(_ args: String...) throws {
                hour += 1
                let date = "\(1_700_000_000 + hour * 3600) +0000"
                try repo.git(args, extraEnvironment: ["GIT_AUTHOR_DATE": date, "GIT_COMMITTER_DATE": date])
            }

            try dated("commit", "-q", "--allow-empty", "-m", "init")
            try repo.git("branch", "develop")
            for release in 1...releases {
                let branch = "release/1.\(release)"
                try repo.git("checkout", "-q", "develop")
                if release == releases {
                    try repo.git("checkout", "-q", "-b", "feature/wip")
                    try dated("commit", "-q", "--allow-empty", "-m", "wip")
                    try repo.git("checkout", "-q", "develop")
                }
                try dated("commit", "-q", "--allow-empty", "-m", "feature \(release)")
                try repo.git("checkout", "-q", "-b", branch)
                if shape == .mergedBack {
                    try dated("commit", "-q", "--allow-empty", "-m", "bump 1.\(release)")
                }
                try repo.git("checkout", "-q", "main")
                try dated("merge", "-q", "--no-ff", "-m", "Merge \(branch)", branch)
                try repo.git("tag", "v1.\(release)")
                if shape == .mergedBack {
                    try repo.git("checkout", "-q", "develop")
                    try dated("merge", "-q", "--no-ff", "-m", "Merge \(branch) into develop", branch)
                }
                try repo.git("branch", "-q", "-D", branch)
            }
            try repo.git("checkout", "-q", "main")
        }
    }

    /// What the app walks for this repo: HEAD, the local branches it doesn't contain and the tags.
    private static func loadLog(_ repo: GitTestRepo) async throws -> [Commit] {
        try await repo.cli.log(refs: ["HEAD", "develop", "feature/wip", "--tags"])
    }

    @Test("Each release merge on main has its second parent on the next row", arguments: ReleaseShape.allCases)
    func releaseSitsBelowItsMerge(shape: ReleaseShape) async throws {
        let repo = try await Self.makeGitflow(shape)
        defer { repo.remove() }
        let log = try await Self.loadLog(repo)
        let rowOf = Dictionary(log.enumerated().map { ($1.sha, $0) }, uniquingKeysWith: { first, _ in first })

        let mainMerges = log.filter { $0.subject.hasPrefix("Merge release/") && !$0.subject.hasSuffix("into develop") }
        #expect(mainMerges.count == Self.releases)
        for merge in mainMerges {
            let mergeRow = try #require(rowOf[merge.sha])
            let releaseRow = try #require(rowOf[merge.parentShas[1]])
            #expect(releaseRow == mergeRow + 1, "\(merge.subject): release on row \(releaseRow), merge on \(mergeRow)")
        }
    }

    /// At most one column each for main, develop, a release and `feature/wip`, where
    /// `--topo-order` needed one more per release.
    @Test("The graph stays four columns wide however many releases there are", arguments: ReleaseShape.allCases)
    func graphStaysNarrow(shape: ReleaseShape) async throws {
        let repo = try await Self.makeGitflow(shape)
        defer { repo.remove() }
        let log = try await Self.loadLog(repo)
        let refs = try await repo.cli.refs()
        let headSha = refs.first { $0.isLocalBranch && $0.isHead }?.targetSha

        let layout = CommitGraphEngine.layout(GraphInput(commits: log, headSha: headSha, refs: refs))
        let widest = layout.rows.map(\.width).max() ?? 0
        #expect(widest <= 4, "widest row needs \(widest) columns")
    }
}
