import Foundation
import Testing
@testable import gitForge

/// `git stash apply` succeeds on a dirty tree as long as local changes don't
/// overlap the stash's paths. Aborting a conflicted apply must therefore
/// undo only what the stash touched — the old `reset --hard HEAD` wiped the
/// user's unrelated work.
@Suite("GitCLI.stashAbortApply", .serialized)
struct GitCLIStashAbortTests {

    /// Builds: a stash that conflicts with HEAD on `conf.txt`, also touches
    /// `clean.txt`, adds `added.txt` to the index and saves the untracked
    /// `loose.txt`; then unrelated staged + unstaged local edits; then a
    /// conflicted apply. Returns the stash SHA.
    private func makeConflictedApply(_ repo: GitTestRepo) throws -> String {
        try repo.commit("init", files: [
            "conf.txt": "base\n", "clean.txt": "clean\n",
            "staged.txt": "s\n", "unstaged.txt": "u\n",
        ])
        try repo.write("from-stash\n", to: "conf.txt")
        try repo.write("clean-from-stash\n", to: "clean.txt")
        try repo.write("added\n", to: "added.txt")
        try repo.git("add", "added.txt")
        try repo.write("loose\n", to: "loose.txt")
        try repo.git("stash", "push", "-q", "--include-untracked")
        let sha = try repo.git("rev-parse", "stash@{0}").trimmingCharacters(in: .whitespacesAndNewlines)

        try repo.write("from-head\n", to: "conf.txt")
        try repo.git("commit", "-qam", "conflicting")

        try repo.write("my staged work\n", to: "staged.txt")
        try repo.git("add", "staged.txt")
        try repo.write("my unstaged work\n", to: "unstaged.txt")

        try repo.git(["stash", "apply"], allowFailure: true)
        #expect(try repo.porcelain().contains("UU conf.txt"))
        return sha
    }

    @Test("Keeps unrelated staged and unstaged changes")
    func keepsUnrelatedWork() async throws {
        let repo = try GitTestRepo()
        defer { repo.remove() }
        let sha = try makeConflictedApply(repo)

        try await repo.cli.stashAbortApply(stashSha: sha)

        #expect(repo.read("staged.txt") == "my staged work\n")
        #expect(repo.read("unstaged.txt") == "my unstaged work\n")
        #expect(try repo.porcelain() == [" M unstaged.txt", "M  staged.txt"])
    }

    @Test("Reverts every path the stash touched, including added and untracked files")
    func revertsStashPaths() async throws {
        let repo = try GitTestRepo()
        defer { repo.remove() }
        let sha = try makeConflictedApply(repo)

        try await repo.cli.stashAbortApply(stashSha: sha)

        #expect(repo.read("conf.txt") == "from-head\n")
        #expect(repo.read("clean.txt") == "clean\n")
        #expect(!repo.exists("added.txt"))
        #expect(!repo.exists("loose.txt"))
        #expect(await repo.cli.mergeState() == .clean)
        // The stash entry survives so the user can retry.
        #expect(try repo.git("stash", "list").contains("stash@{0}"))
    }

    @Test("Without a known stash SHA it falls back to reset --merge and keeps unstaged work")
    func fallbackKeepsUnstagedWork() async throws {
        let repo = try GitTestRepo()
        defer { repo.remove() }
        _ = try makeConflictedApply(repo)

        try await repo.cli.stashAbortApply(stashSha: nil)

        #expect(repo.read("unstaged.txt") == "my unstaged work\n")
        #expect(repo.read("conf.txt") == "from-head\n")
        #expect(await repo.cli.mergeState() == .clean)
    }
}
