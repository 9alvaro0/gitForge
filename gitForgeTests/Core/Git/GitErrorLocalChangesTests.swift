import Foundation
import Testing
@testable import gitForge

@Suite("GitError — local changes in the way")
struct GitErrorLocalChangesTests {

    private static func failure(_ stderr: String) -> String? {
        GitError.commandFailed(args: ["checkout", "--end-of-options", "topic"], exitCode: 1, stderr: stderr).errorDescription
    }

    @Test("Checkout over modified files names them, without the command")
    func checkout() {
        let message = Self.failure("""
            error: Your local changes to the following files would be overwritten by checkout:
            \tbig.txt
            Please commit your changes or stash them before you switch branches.
            Aborting
            """)
        #expect(message == "Your local changes would be overwritten (big.txt). Commit, stash or discard them first.")
    }

    @Test("More than three files are cut short")
    func manyFiles() {
        let message = Self.failure("""
            error: Your local changes to the following files would be overwritten by merge:
            \ta.txt
            \tb.txt
            \tc.txt
            \td.txt
            Please commit your changes or stash them before you merge.
            Aborting
            """)
        #expect(message == "Your local changes would be overwritten (a.txt, b.txt, c.txt, …). Commit, stash or discard them first.")
    }

    @Test("Untracked files in the way")
    func untracked() {
        let message = Self.failure("""
            error: The following untracked working tree files would be overwritten by checkout:
            \tnew.txt
            Please move or remove them before you switch branches.
            Aborting
            """)
        #expect(message == "Untracked files would be overwritten (new.txt). Move or delete them, or commit them first.")
    }

    @Test("Rebase with uncommitted changes")
    func rebase() {
        let message = Self.failure("error: cannot rebase: You have unstaged changes.\nerror: Please commit or stash them.\n")
        #expect(message == "You have uncommitted changes. Commit, stash or discard them before rebasing.")
    }

    @Test("Other failures keep the command and stderr")
    func otherFailures() {
        let message = Self.failure("fatal: invalid reference: topic\n")
        #expect(message?.contains("fatal: invalid reference: topic") == true)
        #expect(message?.contains("git checkout") == true)
    }

    @Test("A real checkout over local changes reads plainly")
    func realCheckout() async throws {
        let repo = try GitTestRepo()
        defer { repo.remove() }
        try repo.commit("init", files: ["a.txt": "a\n"])
        try repo.git("checkout", "-q", "-b", "topic")
        try repo.commit("topic", files: ["a.txt": "topic\n"])
        try repo.git("checkout", "-q", "main")
        try repo.write("local\n", to: "a.txt")

        let error = await #expect(throws: GitError.self) {
            try await repo.cli.checkout(branch: "topic")
        }
        #expect(error?.errorDescription == "Your local changes would be overwritten (a.txt). Commit, stash or discard them first.")
    }
}
