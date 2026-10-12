import Foundation
import Testing
@testable import gitForge

@Suite("GitCLI — stash of selected paths", .serialized)
struct GitCLIStashPathsTests {

    @Test("Only the given paths are stashed, untracked and odd names included")
    func stashesOnlyPaths() async throws {
        let repo = try GitTestRepo()
        defer { repo.remove() }
        try repo.commit("init", files: ["a.txt": "a\n", "b.txt": "b\n"])
        try repo.write("a2\n", to: "a.txt")
        try repo.write("b2\n", to: "b.txt")
        try repo.write("new\n", to: "new.txt")
        // A pathspec glob character and a space: still one literal file.
        try repo.write("odd\n", to: "sp ace*.txt")

        try await repo.cli.stashPush(includeUntracked: true, paths: ["a.txt", "new.txt", "sp ace*.txt"])

        #expect(try repo.porcelain() == [" M b.txt"])
        let stashed = try repo.git("stash", "show", "--include-untracked", "--name-only", "stash@{0}")
            .split(separator: "\n").map(String.init).sorted()
        #expect(stashed == ["a.txt", "new.txt", "sp ace*.txt"])
    }

    @Test("Staged changes of a stashed path go with it")
    func stashesStagedChanges() async throws {
        let repo = try GitTestRepo()
        defer { repo.remove() }
        try repo.commit("init", files: ["a.txt": "a\n", "b.txt": "b\n"])
        try repo.write("a2\n", to: "a.txt")
        try repo.write("b2\n", to: "b.txt")
        try repo.git("add", "a.txt", "b.txt")

        try await repo.cli.stashPush(includeUntracked: false, paths: ["a.txt"])

        #expect(try repo.porcelain() == ["M  b.txt"])
        #expect(repo.read("a.txt") == "a\n")
    }
}
