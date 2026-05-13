import Foundation
import Testing
@testable import gitForge

@Suite("AppState.cleanupPartialClone", .serialized)
@MainActor
struct AppStateCleanupPartialCloneTests {

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitForge-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ contents: String, to file: URL) throws {
        try contents.data(using: .utf8)!.write(to: file)
    }

    @Test("Does nothing when the destination directory does not exist")
    func noOpOnMissingPath() throws {
        let phantom = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitForge-tests-missing-\(UUID().uuidString)")
        // Pre-condition: path must NOT exist.
        #expect(FileManager.default.fileExists(atPath: phantom.path(percentEncoded: false)) == false)
        // Should not throw, should not create anything.
        AppState.cleanupPartialClone(at: phantom)
        #expect(FileManager.default.fileExists(atPath: phantom.path(percentEncoded: false)) == false)
    }

    @Test("Leaves the directory alone when there is no .git inside")
    func leavesNonRepoUntouched() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Simulate a TOCTOU: a non-repo dir the user created themselves.
        try write("user data", to: dir.appendingPathComponent("user-file.txt"))

        AppState.cleanupPartialClone(at: dir)

        // The dir and the user's file must still be there — this is the whole
        // point of the fix.
        #expect(FileManager.default.fileExists(atPath: dir.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("user-file.txt").path(percentEncoded: false)))
    }

    @Test("Removes the directory from its original location when .git is present")
    func removesPartialClone() throws {
        let dir = try makeTempDir()
        // Make it look like a clone in progress: an actual `.git` dir inside.
        let gitDir = dir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try write("config-stub", to: gitDir.appendingPathComponent("config"))
        // Sanity.
        #expect(FileManager.default.fileExists(atPath: gitDir.path(percentEncoded: false)))

        AppState.cleanupPartialClone(at: dir)

        // After cleanup the path must be gone from its original location.
        // (Whether it ended up in Trash vs removed is environment-dependent —
        //  the assertion here only validates "no longer at origin".)
        #expect(FileManager.default.fileExists(atPath: dir.path(percentEncoded: false)) == false)
    }

    @Test("Empty .git directory still counts as 'ours' and triggers removal")
    func emptyGitDirCountsAsOurs() throws {
        let dir = try makeTempDir()
        let gitDir = dir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)

        AppState.cleanupPartialClone(at: dir)
        #expect(FileManager.default.fileExists(atPath: dir.path(percentEncoded: false)) == false)
    }

    @Test(".git as a file (not a dir) also counts — guards the same way")
    func gitAsFileTriggersRemoval() throws {
        let dir = try makeTempDir()
        // A worktree or submodule has `.git` as a file pointing to the real
        // gitdir. The fix uses `fileExists` which matches both — assert that
        // contract so future refactors don't quietly tighten it to "directory".
        try write("gitdir: /elsewhere", to: dir.appendingPathComponent(".git"))

        AppState.cleanupPartialClone(at: dir)
        #expect(FileManager.default.fileExists(atPath: dir.path(percentEncoded: false)) == false)
    }
}
