import Foundation
import Testing
@testable import gitForge

@Suite("GitCLI.headSha", .serialized)
struct GitCLIHeadShaTests {

    @Test("On a branch, HEAD resolves to its tip")
    func onBranch() async throws {
        let repo = try await GitTestRepo.make { try $0.commit("first", files: ["a.txt": "1"]) }
        defer { repo.remove() }
        let expected = try await repo.gitAsync("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(await GitCLI(workingDirectory: repo.url).headSha() == expected)
    }

    @Test("Detached, HEAD resolves to the checked-out commit")
    func detached() async throws {
        let repo = try await GitTestRepo.make {
            try $0.commit("first", files: ["a.txt": "1"])
            try $0.commit("second", files: ["a.txt": "2"])
        }
        defer { repo.remove() }
        let first = try await repo.gitAsync("rev-parse", "HEAD~1").trimmingCharacters(in: .whitespacesAndNewlines)
        try await repo.gitAsync("checkout", "-q", "--detach", first)
        #expect(await GitCLI(workingDirectory: repo.url).headSha() == first)
    }

    @Test("An empty repository has no HEAD commit")
    func unborn() async throws {
        let repo = try await GitTestRepo.make()
        defer { repo.remove() }
        #expect(await GitCLI(workingDirectory: repo.url).headSha() == nil)
    }
}
