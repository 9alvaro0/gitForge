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
}
