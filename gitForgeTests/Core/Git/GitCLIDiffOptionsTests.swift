import Foundation
import Testing
@testable import gitForge

@Suite("Diff options and sign-off", .serialized)
struct GitCLIDiffOptionsTests {

    @Test("An empty -w diff means only whitespace changed")
    func whitespaceOnly() {
        #expect(DiffEmptyState.classifying(raw: "", ignoringWhitespace: true) == .whitespaceOnly)
        #expect(DiffEmptyState.classifying(raw: "\n", ignoringWhitespace: true) == .whitespaceOnly)
        #expect(DiffEmptyState.classifying(raw: "") == .empty)
        // A mode change still reads as a mode change with -w.
        let mode = "diff --git a/run.sh b/run.sh\nold mode 100644\nnew mode 100755\n"
        #expect(DiffEmptyState.classifying(raw: mode, ignoringWhitespace: true)
                == .modeChange(from: "100644", to: "100755"))
    }

    @Test("commit(signOff:) adds the Signed-off-by trailer")
    func signOff() async throws {
        let repo = try GitTestRepo()
        defer { repo.remove() }
        try repo.commit("init", files: ["f.txt": "0\n"])
        try repo.write("1\n", to: "f.txt")
        try repo.git("add", "f.txt")

        try await repo.cli.commit(subject: "signed", signOff: true)

        let message = try repo.git("log", "-1", "--format=%B")
        let email = try repo.git("config", "user.email").trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(message.contains("Signed-off-by:"))
        #expect(message.contains("<\(email)>"))
    }
}

@Suite("WorkingCopyStore — sign-off preference", .serialized)
@MainActor
struct WorkingCopySignOffTests {

    @Test("Remembered per repository")
    func perRepository() {
        TestDefaults.with { suite in
            let cli = GitCLI(workingDirectory: URL(fileURLWithPath: "/var/empty"))
            let a = URL(fileURLWithPath: "/tmp/repo-a")
            let b = URL(fileURLWithPath: "/tmp/repo-b")
            let first = WorkingCopyStore(cli: cli, repositoryURL: a, tasks: OwnedTasks(), defaults: suite.defaults)
            #expect(first.signOff == false)
            first.signOff = true

            let reopened = WorkingCopyStore(cli: cli, repositoryURL: a, tasks: OwnedTasks(), defaults: suite.defaults)
            let other = WorkingCopyStore(cli: cli, repositoryURL: b, tasks: OwnedTasks(), defaults: suite.defaults)
            #expect(reopened.signOff)
            #expect(other.signOff == false)
        }
    }

    @Test("A conflicted file diffs against HEAD, conflict markers included")
    func conflictedFile() async throws {
        let repo = try GitTestRepo()
        defer { repo.remove() }
        try repo.commit("init", files: ["a.txt": "base\n"])
        try repo.git("checkout", "-q", "-b", "other")
        try repo.commit("other", files: ["a.txt": "theirs\n"])
        try repo.git("checkout", "-q", "main")
        try repo.commit("main", files: ["a.txt": "ours\n"])
        _ = try repo.git(["merge", "other"], allowFailure: true)

        // Plain diff is a combined one the parser can't read.
        #expect(DiffParser.parse(try await repo.cli.diffUnstaged(file: "a.txt")).isEmpty)
        let hunks = DiffParser.parse(try await repo.cli.diffAgainstHead(file: "a.txt"))
        let added = hunks.flatMap(\.lines).filter { $0.kind == .added }.map(\.content)
        #expect(added.contains { $0.hasPrefix("<<<<<<<") })
        #expect(added.contains("theirs"))
    }

    @Test("A staged rename diffs against its old path, not as a new file")
    func stagedRename() async throws {
        let repo = try GitTestRepo()
        defer { repo.remove() }
        try repo.commit("init", files: ["old.txt": "a\nb\nc\n"])
        try repo.git("mv", "old.txt", "new.txt")
        try repo.write("a\nb\nc\nd\n", to: "new.txt")
        try repo.git("add", "new.txt")

        let hunks = DiffParser.parse(try await repo.cli.diffStaged(file: "new.txt", originalPath: "old.txt"))
        let added = hunks.flatMap(\.lines).filter { $0.kind == .added }.map(\.content)
        #expect(added == ["d"])
    }
}
