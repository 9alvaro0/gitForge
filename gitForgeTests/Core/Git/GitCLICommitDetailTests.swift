import Foundation
import Testing
@testable import gitForge

/// Root and merge commits used to show zero files in the commit detail:
/// `diff-tree` prints nothing for them without `--root` and a merge mode.
@Suite("GitCLI.commitDetail — root & merge commits", .serialized)
struct GitCLICommitDetailTests {

    private func commit(_ repo: GitTestRepo, _ sha: String) async throws -> Commit {
        let commits = try await repo.cli.log(limit: 50, refs: ["--all"])
        return try #require(commits.first { $0.sha == sha })
    }

    @Test("Root commit lists its files and has a diff")
    func rootCommit() async throws {
        let repo = try GitTestRepo()
        defer { repo.remove() }
        let root = try repo.commit("root", files: ["a.txt": "a\n"])

        let detail = try await repo.cli.commitDetail(for: try await commit(repo, root))
        #expect(detail.files.map(\.path) == ["a.txt"])

        let raw = try await repo.cli.diff(sha: root, file: "a.txt")
        #expect(DiffParser.parse(raw).count == 1)
    }

    @Test("Merge commit lists what it brought in relative to its first parent")
    func mergeCommit() async throws {
        let repo = try GitTestRepo()
        defer { repo.remove() }
        try repo.commit("root", files: ["base.txt": "b\n"])
        try repo.git("checkout", "-q", "-b", "feature")
        try repo.commit("feature", files: ["feature.txt": "f\n"])
        try repo.git("checkout", "-q", "main")
        try repo.commit("main", files: ["main.txt": "m\n"])
        try repo.git("merge", "-q", "--no-edit", "feature")
        let merge = try repo.git("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)

        let detail = try await repo.cli.commitDetail(for: try await commit(repo, merge))
        #expect(detail.files.map(\.path) == ["feature.txt"])

        let raw = try await repo.cli.diff(sha: merge, file: "feature.txt")
        #expect(DiffParser.parse(raw).count == 1)
    }
}
