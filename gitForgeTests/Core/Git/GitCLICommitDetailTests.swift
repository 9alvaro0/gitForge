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

    @Test("An unsigned commit has no signature")
    func unsignedCommit() async throws {
        let repo = try GitTestRepo()
        defer { repo.remove() }
        let sha = try repo.commit("root", files: ["a.txt": "a\n"])

        let detail = try await repo.cli.commitDetail(for: try await commit(repo, sha))
        #expect(detail.signature == nil)
        #expect(await repo.cli.signature(of: sha) == nil)
    }

    @Test("An SSH signature is verified, or can't be verified when its tool won't start",
          .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/ssh-keygen")))
    func sshSignature() async throws {
        let repo = try GitTestRepo()
        defer { repo.remove() }
        let key = repo.url.appendingPathComponent(".signkey").path(percentEncoded: false)
        try Self.run("/usr/bin/ssh-keygen", ["-q", "-t", "ed25519", "-N", "", "-C", "test@example.com", "-f", key])
        let publicKey = try String(contentsOfFile: key + ".pub", encoding: .utf8)
            .split(separator: " ").prefix(2).joined(separator: " ")
        try repo.write("test@example.com \(publicKey)\n", to: ".allowed_signers")
        try repo.git("config", "gpg.format", "ssh")
        try repo.git("config", "gpg.ssh.program", "/usr/bin/ssh-keygen")
        try repo.git("config", "gpg.ssh.allowedSignersFile", repo.url.appendingPathComponent(".allowed_signers").path(percentEncoded: false))
        try repo.git("config", "user.signingkey", key + ".pub")
        try repo.write("a\n", to: "a.txt")
        try repo.git("add", "a.txt")
        try repo.git("commit", "-q", "-S", "-m", "signed")
        let sha = try repo.git("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)

        #expect(await repo.cli.signature(of: sha)?.status == .verified)

        try repo.git("config", "gpg.ssh.program", "/nonexistent/ssh-keygen")
        #expect(await repo.cli.signature(of: sha)?.status == .unverifiable)
    }

    private static func run(_ executable: String, _ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        exited.wait()
    }
}
