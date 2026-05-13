import Foundation
import Testing
@testable import gitForge

@Suite("GitCLI.deleteUntracked", .serialized)
struct GitCLIDeleteUntrackedTests {

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitForge-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ contents: String, to file: URL) throws {
        try contents.data(using: .utf8)!.write(to: file)
    }

    @Test("Empty path list is a no-op (doesn't throw, doesn't touch the worktree)")
    func emptyListNoOp() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try write("keep me", to: dir.appendingPathComponent("untouched.txt"))

        let cli = GitCLI(workingDirectory: dir)
        try await cli.deleteUntracked(paths: [])

        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("untouched.txt").path(percentEncoded: false)))
    }

    @Test("Removes a single untracked file from its original location")
    func removesSingleFile() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("doomed.txt")
        try write("bye", to: target)

        let cli = GitCLI(workingDirectory: dir)
        try await cli.deleteUntracked(paths: ["doomed.txt"])

        // The file must be gone from the user's worktree. Whether it ended up
        // in Trash or got hard-removed is environment-dependent (sandboxed
        // CI runners can't talk to Finder), so we only assert "not at origin".
        #expect(FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) == false)
    }

    @Test("Removes multiple files in one call")
    func removesMultipleFiles() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.txt")
        let b = dir.appendingPathComponent("b.txt")
        try write("a", to: a)
        try write("b", to: b)

        let cli = GitCLI(workingDirectory: dir)
        try await cli.deleteUntracked(paths: ["a.txt", "b.txt"])

        #expect(FileManager.default.fileExists(atPath: a.path(percentEncoded: false)) == false)
        #expect(FileManager.default.fileExists(atPath: b.path(percentEncoded: false)) == false)
    }

    @Test("Handles nested paths (subdirectories) the same way as top-level paths")
    func removesNestedFile() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let nestedDir = dir.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        let target = nestedDir.appendingPathComponent("deep.txt")
        try write("deep", to: target)

        let cli = GitCLI(workingDirectory: dir)
        try await cli.deleteUntracked(paths: ["nested/deep.txt"])

        #expect(FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) == false)
        // The parent dir must NOT have been removed — we only target the leaf.
        #expect(FileManager.default.fileExists(atPath: nestedDir.path(percentEncoded: false)))
    }

    @Test("Silently skips files that don't exist (no throw)")
    func skipsMissing() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let cli = GitCLI(workingDirectory: dir)
        // Should NOT throw — the function is best-effort by design (otherwise
        // a partial-success discard would leave the UI in an inconsistent state).
        try await cli.deleteUntracked(paths: ["nope-not-here.txt"])
    }
}
