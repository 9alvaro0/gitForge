import Foundation
import Testing
@testable import gitForge

/// Real hooks in a throwaway repo (#58). Before the fix every command ran
/// under the network idle watchdog, so a `pre-commit` that printed nothing
/// for longer than the timeout was killed and reported as an unreachable
/// remote. The watchdog polls every 5 s, so with a 1 s timeout a hook that
/// sleeps 7 s silently is past it on the second poll.
@Suite("GitCLI — local hooks", .serialized)
struct GitCLIHooksTests {

    /// A one-second setting, injected so the suite never writes the shared
    /// `UserDefaults` other tests read.
    private static func cli(_ repo: GitTestRepo) -> GitCLI {
        GitCLI(workingDirectory: repo.url, configuredTimeoutSeconds: { 1 })
    }

    private static func makeRepo() async throws -> GitTestRepo {
        try await GitTestRepo.make { try $0.commit("first", files: ["a.txt": "1"]) }
    }

    private static func headSubject(_ repo: GitTestRepo) async throws -> String {
        try await repo.gitAsync("log", "-1", "--format=%s").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test("A silent pre-commit that outlives the idle timeout still produces the commit")
    func slowSilentPreCommitCommits() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        try await repo.installHookAsync("pre-commit", script: "sleep 7\nexit 0")
        try await repo.perform { try $0.write("2", to: "a.txt"); try $0.git("add", "a.txt") }

        try await Self.cli(repo).commit(subject: "slow hook")

        #expect(try await Self.headSubject(repo) == "slow hook")
    }

    @Test("A silent local command killed by the watchdog doesn't blame the remote")
    func localTimeoutDoesNotMentionRemote() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        // `checkout` is local but doesn't commit, so it keeps the short
        // timeout; its post-checkout hook stays silent past it. The watchdog
        // polls every few seconds and a loaded runner delays it further, so
        // the hook outlasts any delay. `exec` with its output sent elsewhere:
        // once git is killed nothing holds git's pipes open, and the test
        // ends with the kill rather than with the sleep.
        try await repo.installHookAsync("post-checkout", script: "exec sleep 60 >/dev/null 2>&1")

        let error = await #expect(throws: GitError.self) {
            try await Self.cli(repo).run(["checkout", "-q", "-b", "side"])
        }
        guard case .commandFailed(_, _, let stderr)? = error else {
            Issue.record("expected commandFailed, got \(String(describing: error))")
            return
        }
        #expect(stderr == GitCommandKind.local.timeoutMessage(after: 1))
        let message = error?.userMessage ?? ""
        #expect(!message.lowercased().contains("remote"), "\(message)")
        #expect(RemoteFailure(stderr: stderr) != .network)
    }

    @Test("A failing pre-commit throws with the hook's stdout and stderr in stderr")
    func failingHookOutput() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        try await repo.installHookAsync("pre-commit", script: "echo 'lint: 2 problems'\necho 'src/a.js:1 no-var' >&2\nexit 1")
        try await repo.perform { try $0.write("2", to: "a.txt"); try $0.git("add", "a.txt") }

        let error = await #expect(throws: GitError.self) {
            try await Self.cli(repo).commit(subject: "blocked")
        }
        guard case .commandFailed(_, _, let stderr)? = error else {
            Issue.record("expected commandFailed, got \(String(describing: error))")
            return
        }
        #expect(stderr.contains("lint: 2 problems"))
        #expect(stderr.contains("src/a.js:1 no-var"))
        #expect(try await Self.headSubject(repo) == "first")
    }

    @Test("skipHooks commits past a failing pre-commit and commit-msg")
    func skipHooksCommits() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        try await repo.installHookAsync("pre-commit", script: "exit 1")
        try await repo.installHookAsync("commit-msg", script: "exit 1")
        try await repo.perform { try $0.write("2", to: "a.txt"); try $0.git("add", "a.txt") }

        try await Self.cli(repo).commit(subject: "no verify", skipHooks: true)

        #expect(try await Self.headSubject(repo) == "no verify")
    }

    @Test("installedHooks lists executable hooks only, from core.hooksPath")
    func installedHooks() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        #expect(await repo.cli.installedHooks(HookFailure.commitHooks).isEmpty)

        try await repo.installHookAsync("pre-commit", script: "exit 0")
        try await repo.installHookAsync("commit-msg", script: "exit 0", executable: false)

        #expect(await repo.cli.installedHooks(HookFailure.commitHooks) == ["pre-commit"])
    }

    @Test("installedHooks finds hooks in the default .git/hooks folder")
    func installedHooksDefaultFolder() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        try await repo.perform { repo in
            // Pin the default location in case the developer has a global hooksPath.
            try repo.git("config", "core.hooksPath", ".git/hooks")
            let hook = repo.url.appendingPathComponent(".git/hooks/commit-msg")
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: hook)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path(percentEncoded: false))
        }

        #expect(await repo.cli.installedHooks(HookFailure.commitHooks) == ["commit-msg"])
    }
}
