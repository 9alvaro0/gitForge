import Foundation
import Testing
@testable import gitForge

@Suite("GitCLI.renameBranch", .serialized)
struct GitCLIRenameBranchTests {

    private static func makeRepo() async throws -> GitTestRepo {
        try await GitTestRepo.make {
            try $0.commit("first", files: ["a.txt": "1"])
            try $0.git("branch", "feat/old")
        }
    }

    private static func localBranches(in repo: GitTestRepo) async throws -> [String] {
        try await repo.gitAsync("for-each-ref", "--format=%(refname:short)", "refs/heads/")
            .split(separator: "\n").map(String.init).sorted()
    }

    @Test("Renames a branch that isn't checked out")
    func renamesOtherBranch() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }

        try await repo.cli.renameBranch(from: "feat/old", to: "feat/new")

        #expect(try await Self.localBranches(in: repo) == ["feat/new", "main"])
        #expect(await repo.cli.currentBranchName() == "main")
    }

    @Test("Renames the checked-out branch and HEAD follows it")
    func renamesCurrentBranch() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }

        try await repo.cli.renameBranch(from: "main", to: "trunk")

        #expect(await repo.cli.currentBranchName() == "trunk")
        #expect(try await Self.localBranches(in: repo) == ["feat/old", "trunk"])
    }

    @Test("Keeps the upstream the branch tracked")
    func keepsUpstream() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        try await repo.gitAsync("config", "branch.feat/old.remote", "origin")
        try await repo.gitAsync("config", "branch.feat/old.merge", "refs/heads/feat/old")

        try await repo.cli.renameBranch(from: "feat/old", to: "feat/new")

        let merge = try await repo.gitAsync("config", "branch.feat/new.merge")
        #expect(merge.trimmingCharacters(in: .whitespacesAndNewlines) == "refs/heads/feat/old")
    }

    @Test("Refuses a name another branch already has")
    func refusesExistingName() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }

        await #expect(throws: (any Error).self) {
            try await repo.cli.renameBranch(from: "feat/old", to: "main")
        }
        #expect(try await Self.localBranches(in: repo) == ["feat/old", "main"])
    }

    @Test("A new name starting with a dash is taken as a name, not an option")
    func dashNameIsNotAnOption() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }

        // git rejects `-x` as a branch name; what matters is that it fails
        // instead of reading `--force` and clobbering `main`.
        await #expect(throws: (any Error).self) {
            try await repo.cli.renameBranch(from: "feat/old", to: "--force")
        }
        #expect(try await Self.localBranches(in: repo) == ["feat/old", "main"])
    }
}
