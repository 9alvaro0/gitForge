import Foundation
import Testing
@testable import gitForge

@Suite("GitCLI — tag refspecs & stash untracked files", .serialized)
struct GitCLITagAndStashFilesTests {

    @Test("tagRef qualifies bare names and leaves full refs alone")
    func tagRefQualifies() {
        #expect(GitCLI.tagRef("v1") == "refs/tags/v1")
        #expect(GitCLI.tagRef("refs/tags/v1") == "refs/tags/v1")
    }

    @Test("Deleting a remote tag never deletes a same-named remote branch")
    func pushDeleteTagSparesBranch() async throws {
        let remote = try GitTestRepo(bare: true)
        let repo = try GitTestRepo()
        defer { remote.remove(); repo.remove() }
        try repo.commit("init", files: ["f.txt": "f\n"])
        try repo.git("remote", "add", "origin", remote.url.path(percentEncoded: false))
        try repo.git("push", "-q", "origin", "main:v1")

        // There's no tag `v1` on the remote, only a branch. git only warns
        // about deleting a missing ref; with a bare `v1` refspec it would
        // have deleted the branch instead.
        try await repo.cli.pushDeleteTag(name: "v1")
        #expect(try remote.git("branch", "--list", "v1").contains("v1"))
    }

    @Test("Stash detail lists untracked files and can diff them")
    func stashListsUntrackedFiles() async throws {
        let repo = try GitTestRepo()
        defer { repo.remove() }
        try repo.commit("init", files: ["tracked.txt": "t\n"])
        try repo.write("t2\n", to: "tracked.txt")
        try repo.write("one\ntwo\n", to: "new.txt")
        try repo.git("stash", "push", "-q", "--include-untracked")

        let files = try await repo.cli.stashFiles(index: 0)
        #expect(files.first { $0.path == "tracked.txt" }?.status == .modified)
        let untracked = try #require(files.first { $0.path == "new.txt" })
        #expect(untracked.status == .untracked)
        #expect(untracked.additions == 2)

        let raw = try await repo.cli.stashFileDiff(index: 0, path: "new.txt", untracked: true)
        #expect(DiffParser.parse(raw).first?.lines.count == 2)
    }

    @Test("Stash without untracked files lists only tracked changes")
    func stashWithoutUntracked() async throws {
        let repo = try GitTestRepo()
        defer { repo.remove() }
        try repo.commit("init", files: ["tracked.txt": "t\n"])
        try repo.write("t2\n", to: "tracked.txt")
        try repo.git("stash", "push", "-q")

        let files = try await repo.cli.stashFiles(index: 0)
        #expect(files.map(\.path) == ["tracked.txt"])
    }
}
