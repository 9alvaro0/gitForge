import Foundation
import Testing
@testable import gitForge

@Suite("GitCLI.headBranch", .serialized)
struct GitCLIHeadBranchTests {

    @Test("On a branch, HEAD names it")
    func onBranch() async throws {
        let repo = try await GitTestRepo.make { try $0.commit("first", files: ["a.txt": "1"]) }
        defer { repo.remove() }
        #expect(try await GitCLI(workingDirectory: repo.url).headBranch() == .branch("main"))
    }

    @Test("Detached, HEAD names no branch")
    func detached() async throws {
        let repo = try await GitTestRepo.make { try $0.commit("first", files: ["a.txt": "1"]) }
        defer { repo.remove() }
        try await repo.gitAsync("checkout", "-q", "--detach")
        #expect(try await GitCLI(workingDirectory: repo.url).headBranch() == .detached)
    }

    @Test("An empty repository is on its unborn branch")
    func unborn() async throws {
        let repo = try await GitTestRepo.make()
        defer { repo.remove() }
        #expect(try await GitCLI(workingDirectory: repo.url).headBranch() == .branch("main"))
    }

    @Test("A failed read throws instead of reporting a detached HEAD")
    func failedReadThrows() async throws {
        // A plain directory: git exits 128 ("not a git repository"), which is
        // not the "HEAD is not a symbolic ref" answer.
        let url = TemporaryDirectories.make("gitForge-not-a-repo")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: GitError.self) {
            try await GitCLI(workingDirectory: url).headBranch()
        }
    }

    @Test("currentBranchName keeps returning nil when detached")
    func currentBranchNameWhenDetached() async throws {
        let repo = try await GitTestRepo.make { try $0.commit("first", files: ["a.txt": "1"]) }
        defer { repo.remove() }
        let cli = GitCLI(workingDirectory: repo.url)
        #expect(await cli.currentBranchName() == "main")
        try await repo.gitAsync("checkout", "-q", "--detach")
        #expect(await cli.currentBranchName() == nil)
    }
}
