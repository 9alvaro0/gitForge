import Foundation
import Testing
@testable import gitForge

@Suite("GitCLI — stash of selected paths", .serialized)
struct GitCLIStashPathsTests {

    @Test("Only the given paths are stashed, untracked and odd names included")
    func stashesOnlyPaths() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("init", files: ["a.txt": "a\n", "b.txt": "b\n"])
            try repo.write("a2\n", to: "a.txt")
            try repo.write("b2\n", to: "b.txt")
            try repo.write("new\n", to: "new.txt")
            // A pathspec glob character and a space: still one literal file.
            try repo.write("odd\n", to: "sp ace*.txt")
        }
        defer { repo.remove() }

        try await repo.cli.stashPush(includeUntracked: true, paths: ["a.txt", "new.txt", "sp ace*.txt"])

        #expect(try await repo.porcelainAsync() == [" M b.txt"])
        let stashed = try await repo.gitAsync("stash", "show", "--include-untracked", "--name-only", "stash@{0}")
            .split(separator: "\n").map(String.init).sorted()
        #expect(stashed == ["a.txt", "new.txt", "sp ace*.txt"])
    }

    @Test("Staged changes of a stashed path go with it")
    func stashesStagedChanges() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("init", files: ["a.txt": "a\n", "b.txt": "b\n"])
            try repo.write("a2\n", to: "a.txt")
            try repo.write("b2\n", to: "b.txt")
            try repo.git("add", "a.txt", "b.txt")
        }
        defer { repo.remove() }

        try await repo.cli.stashPush(includeUntracked: false, paths: ["a.txt"])

        #expect(try await repo.porcelainAsync() == ["M  b.txt"])
        #expect(repo.read("a.txt") == "a\n")
    }

    @Test("Other staged files stay out of the stash, and a pop brings back only the paths")
    func otherStagedFilesStayOut() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("init", files: ["a.txt": "a\n", "b.txt": "b\n"])
            try repo.write("a2\n", to: "a.txt")
            try repo.write("b2\n", to: "b.txt")
            try repo.git("add", "a.txt", "b.txt")
            try repo.write("a3\n", to: "a.txt")
        }
        defer { repo.remove() }

        try await repo.cli.stashPush(includeUntracked: false, paths: ["a.txt"])

        #expect(try await repo.gitAsync("stash", "list").split(separator: "\n").count == 1)
        #expect(try await repo.gitAsync("stash", "list").contains("WIP on main"))
        let worktree = try await repo.gitAsync("diff", "--name-only", "stash@{0}^1", "stash@{0}")
        #expect(worktree == "a.txt\n")
        let index = try await repo.gitAsync("diff", "--name-only", "stash@{0}^1", "stash@{0}^2")
        #expect(index == "a.txt\n")
        #expect(try await repo.gitAsync("show", "stash@{0}^2:a.txt") == "a2\n")
        #expect(try await repo.gitAsync("show", "stash@{0}:a.txt") == "a3\n")

        // b.txt is restaged with new content after the stash. With git's
        // wider stash the pop below conflicts on b.txt; narrowed, it leaves
        // b.txt alone.
        try await repo.perform { repo in
            try repo.write("b3\n", to: "b.txt")
            try repo.git("add", "b.txt")
            try repo.git("stash", "pop")
        }
        #expect(repo.read("a.txt") == "a3\n")
        #expect(repo.read("b.txt") == "b3\n")
        #expect(try await repo.porcelainAsync() == [" M a.txt", "M  b.txt"])
    }

    @Test("An untracked pick keeps other staged files out")
    func untrackedPickWithOtherStaged() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("init", files: ["b.txt": "b\n"])
            try repo.write("b2\n", to: "b.txt")
            try repo.git("add", "b.txt")
            try repo.write("new\n", to: "new.txt")
        }
        defer { repo.remove() }

        try await repo.cli.stashPush(includeUntracked: true, paths: ["new.txt"])

        #expect(try await repo.porcelainAsync() == ["M  b.txt"])
        #expect(try await repo.gitAsync("diff", "--name-only", "stash@{0}^1", "stash@{0}") == "")
        #expect(try await repo.gitAsync("show", "stash@{0}^3:new.txt") == "new\n")
    }
}
