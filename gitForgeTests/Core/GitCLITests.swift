import Foundation
import Testing
@testable import gitForge

@Suite("GitCLI")
struct GitCLITests {
    let tempRepo: URL
    let cli: GitCLI

    init() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitForge-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        self.tempRepo = dir
        self.cli = GitCLI(workingDirectory: dir)

        try await cli.run(["init", "-b", "main"])
        try await cli.run(["config", "user.email", "test@gitforge.local"])
        try await cli.run(["config", "user.name", "Test User"])
        try await cli.run(["commit", "--allow-empty", "-m", "initial"])
    }

    private func cleanup() {
        try? FileManager.default.removeItem(at: tempRepo)
    }

    @Test("Successful command returns exit code 0 and captured stdout")
    func successfulCommandReturnsResult() async throws {
        defer { cleanup() }
        let result = try await cli.run(["rev-parse", "--abbrev-ref", "HEAD"])
        #expect(result.isSuccess)
        #expect(result.exitCode == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "main")
    }

    @Test("Status output reflects working tree state")
    func statusReturnsCleanOnFreshRepo() async throws {
        defer { cleanup() }
        let result = try await cli.run(["status", "--porcelain"])
        #expect(result.isSuccess)
        #expect(result.stdout.isEmpty)
    }

    @Test("Failing command throws commandFailed with parsed exit code and stderr")
    func failingCommandThrowsCommandFailed() async throws {
        defer { cleanup() }
        do {
            _ = try await cli.run(["checkout", "branch-that-does-not-exist"])
            Issue.record("Expected GitError.commandFailed to be thrown")
        } catch let GitError.commandFailed(args, exitCode, stderr) {
            #expect(args == ["checkout", "branch-that-does-not-exist"])
            #expect(exitCode != 0)
            #expect(!stderr.isEmpty)
        }
    }

    @Test("Invalid working directory throws invalidWorkingDirectory")
    func invalidWorkingDirectoryThrows() async throws {
        defer { cleanup() }
        let bogus = URL(fileURLWithPath: "/path/that/does/not/exist-\(UUID().uuidString)")
        let bogusCli = GitCLI(workingDirectory: bogus)
        await #expect(throws: GitError.invalidWorkingDirectory(bogus)) {
            try await bogusCli.run(["status"])
        }
    }

    @Test("Duration is positive for any executed command")
    func durationIsRecorded() async throws {
        defer { cleanup() }
        let result = try await cli.run(["--version"])
        #expect(result.duration > 0)
    }

    @Test("Outputs larger than the pipe buffer are captured fully")
    func largeOutputIsCapturedWithoutDeadlock() async throws {
        defer { cleanup() }
        // Create many commits to force a multi-KB log output that may exceed
        // the typical 64KB pipe buffer once detailed.
        for i in 1...500 {
            try await cli.run(["commit", "--allow-empty", "-m", "Commit number \(i) with extra padding to grow the log output beyond a single pipe buffer"])
        }
        let result = try await cli.run(["log", "--format=%H %s"])
        #expect(result.isSuccess)
        let lineCount = result.stdout.split(separator: "\n").count
        #expect(lineCount == 501) // 500 + initial empty commit
    }
}
