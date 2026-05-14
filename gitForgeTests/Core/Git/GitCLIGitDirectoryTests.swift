import Foundation
import Testing
@testable import gitForge

@Suite("GitCLI — resolveGitDirectory / resolveGitCommonDirectory", .serialized)
struct GitCLIGitDirectoryTests {

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitForge-gitdir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: resolveGitDirectory

    @Test("Returns nil when the path doesn't contain a .git entry")
    func nilForPlainDir() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(GitCLI.resolveGitDirectory(in: dir) == nil)
    }

    @Test("Returns <worktree>/.git when .git is a directory (regular repo)")
    func resolvesDirectoryGitDir() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let gitDir = dir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)

        let resolved = GitCLI.resolveGitDirectory(in: dir)
        #expect(resolved?.standardizedFileURL == gitDir.standardizedFileURL)
    }

    @Test("Resolves an absolute gitdir path written in .git (linked worktree)")
    func resolvesAbsoluteGitdirFile() throws {
        let worktree = try makeTempDir()
        let mainGitDir = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: worktree)
            try? FileManager.default.removeItem(at: mainGitDir)
        }
        // .git in the worktree is a file pointing at the main repo's
        // worktrees/<name> directory. Absolute path form.
        let dotGit = worktree.appendingPathComponent(".git")
        try "gitdir: \(mainGitDir.path(percentEncoded: false))\n".data(using: .utf8)!.write(to: dotGit)

        let resolved = GitCLI.resolveGitDirectory(in: worktree)
        #expect(resolved?.standardizedFileURL == mainGitDir.standardizedFileURL)
    }

    @Test("Resolves a relative gitdir path written in .git (also valid)")
    func resolvesRelativeGitdirFile() throws {
        let worktree = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: worktree) }
        let target = worktree.appendingPathComponent("nested/gitdir")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let dotGit = worktree.appendingPathComponent(".git")
        try "gitdir: nested/gitdir\n".data(using: .utf8)!.write(to: dotGit)

        let resolved = GitCLI.resolveGitDirectory(in: worktree)
        #expect(resolved?.standardizedFileURL == target.standardizedFileURL)
    }

    @Test("Returns nil when the .git file doesn't start with the gitdir prefix")
    func rejectsMalformedGitFile() throws {
        let worktree = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: worktree) }
        let dotGit = worktree.appendingPathComponent(".git")
        try "not a gitdir marker\n".data(using: .utf8)!.write(to: dotGit)

        #expect(GitCLI.resolveGitDirectory(in: worktree) == nil)
    }

    // MARK: resolveGitCommonDirectory

    @Test("Common dir == git dir for a regular (non-worktree) repo")
    func commonDirEqualsGitDirForRegularRepo() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let gitDir = dir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)

        let resolved = GitCLI.resolveGitCommonDirectory(in: dir)
        #expect(resolved?.standardizedFileURL == gitDir.standardizedFileURL)
    }

    @Test("Resolves commondir file content (absolute) to the main repo's gitdir")
    func commonDirAbsolute() throws {
        let worktree = try makeTempDir()
        let perWorktreeGitDir = try makeTempDir()
        let mainCommonDir = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: worktree)
            try? FileManager.default.removeItem(at: perWorktreeGitDir)
            try? FileManager.default.removeItem(at: mainCommonDir)
        }
        // worktree/.git → file pointing at per-worktree gitdir.
        try "gitdir: \(perWorktreeGitDir.path(percentEncoded: false))\n"
            .data(using: .utf8)!
            .write(to: worktree.appendingPathComponent(".git"))
        // per-worktree gitdir/commondir → absolute path to main repo's gitdir.
        try "\(mainCommonDir.path(percentEncoded: false))\n"
            .data(using: .utf8)!
            .write(to: perWorktreeGitDir.appendingPathComponent("commondir"))

        let resolved = GitCLI.resolveGitCommonDirectory(in: worktree)
        #expect(resolved?.standardizedFileURL == mainCommonDir.standardizedFileURL)
    }

    @Test("Resolves commondir file content (relative) to a path relative to the per-worktree gitdir")
    func commonDirRelative() throws {
        let worktree = try makeTempDir()
        let perWorktreeGitDir = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: worktree)
            try? FileManager.default.removeItem(at: perWorktreeGitDir)
        }
        try "gitdir: \(perWorktreeGitDir.path(percentEncoded: false))\n"
            .data(using: .utf8)!
            .write(to: worktree.appendingPathComponent(".git"))
        try "../shared\n"
            .data(using: .utf8)!
            .write(to: perWorktreeGitDir.appendingPathComponent("commondir"))

        let expected = perWorktreeGitDir.appendingPathComponent("../shared").standardizedFileURL
        let resolved = GitCLI.resolveGitCommonDirectory(in: worktree)
        #expect(resolved?.standardizedFileURL == expected)
    }
}
