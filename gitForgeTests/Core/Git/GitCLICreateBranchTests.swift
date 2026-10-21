import Foundation
import Testing
@testable import gitForge

@Suite("GitCLI.createBranch", .serialized)
struct GitCLICreateBranchTests {

    private static func makeRepo() async throws -> (repo: GitTestRepo, first: String, second: String) {
        let repo = try await GitTestRepo.make {
            try $0.commit("first", files: ["a.txt": "1"])
            try $0.commit("second", files: ["a.txt": "2"])
        }
        let first = try await repo.gitAsync("rev-parse", "HEAD~1").trimmingCharacters(in: .whitespacesAndNewlines)
        let second = try await repo.gitAsync("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
        return (repo, first, second)
    }

    private static func tip(of branch: String, in repo: GitTestRepo) async throws -> String {
        try await repo.gitAsync("rev-parse", "refs/heads/\(branch)").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func localBranches(in repo: GitTestRepo) async throws -> [String] {
        try await repo.gitAsync("for-each-ref", "--format=%(refname:short)", "refs/heads/")
            .split(separator: "\n").map(String.init).sorted()
    }

    @Test("Checkout without a start point branches off HEAD and switches to it")
    func checkoutFromHead() async throws {
        let (repo, _, second) = try await Self.makeRepo()
        defer { repo.remove() }

        try await repo.cli.createBranch("feat/new-thing", checkout: true)

        #expect(await repo.cli.currentBranchName() == "feat/new-thing")
        #expect(try await Self.tip(of: "feat/new-thing", in: repo) == second)
    }

    @Test("Checkout with a start point branches off it and switches to it")
    func checkoutFromStartPoint() async throws {
        let (repo, first, _) = try await Self.makeRepo()
        defer { repo.remove() }

        try await repo.cli.createBranch("feat/from-first", startingAt: first, checkout: true)

        #expect(await repo.cli.currentBranchName() == "feat/from-first")
        #expect(await repo.cli.headSha() == first)
    }

    @Test("Checkout from a remote-tracking branch with a nested name (pull request checkout)")
    func checkoutFromRemoteTrackingBranch() async throws {
        let (repo, first, _) = try await Self.makeRepo()
        defer { repo.remove() }
        try await repo.gitAsync("update-ref", "refs/remotes/origin/david/hooks/02-vertical-slice", first)

        try await repo.cli.createBranch("david/hooks/02-vertical-slice",
                                        startingAt: "origin/david/hooks/02-vertical-slice",
                                        checkout: true)

        #expect(await repo.cli.currentBranchName() == "david/hooks/02-vertical-slice")
        #expect(await repo.cli.headSha() == first)
    }

    @Test("Without checkout the branch is created and HEAD stays put")
    func createWithoutCheckout() async throws {
        let (repo, first, second) = try await Self.makeRepo()
        defer { repo.remove() }

        try await repo.cli.createBranch("feat/at-head")
        try await repo.cli.createBranch("feat/at-first", startingAt: first)

        #expect(await repo.cli.currentBranchName() == "main")
        #expect(try await Self.tip(of: "feat/at-head", in: repo) == second)
        #expect(try await Self.tip(of: "feat/at-first", in: repo) == first)
    }

    @Test("A name starting with '-' is refused as a name, never read as a flag",
          arguments: [true, false])
    func dashLedNameIsNotAFlag(checkout: Bool) async throws {
        let (repo, _, _) = try await Self.makeRepo()
        defer { repo.remove() }

        // `--no-track` is a real flag of both `checkout -b` and `branch`.
        await #expect(throws: GitError.self) {
            try await repo.cli.createBranch("--no-track", startingAt: "HEAD", checkout: checkout)
        }
        #expect(await repo.cli.currentBranchName() == "main")
        #expect(try await Self.localBranches(in: repo) == ["main"])
    }

    @Test("A start point starting with '-' is read as a revision, never as a flag",
          arguments: [true, false])
    func dashLedStartPointIsNotAFlag(checkout: Bool) async throws {
        let (repo, _, _) = try await Self.makeRepo()
        defer { repo.remove() }

        // Read as the `--no-track` flag, git would happily branch off HEAD.
        await #expect(throws: GitError.self) {
            try await repo.cli.createBranch("feat/x", startingAt: "--no-track", checkout: checkout)
        }
        #expect(await repo.cli.currentBranchName() == "main")
        #expect(try await Self.localBranches(in: repo) == ["main"])
    }
}
