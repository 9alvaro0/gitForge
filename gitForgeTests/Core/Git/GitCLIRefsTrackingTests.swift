import Foundation
import Testing
@testable import gitForge

@Suite("GitCLI.refs — upstream tracking", .serialized)
struct GitCLIRefsTrackingTests {

    @Test("A branch ahead of and behind its upstream reports both, with its tip subject")
    func aheadBehind() async throws {
        let remote = try await GitTestRepo.make(bare: true)
        defer { remote.remove() }
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("base", files: ["a.txt": "1"])
            try repo.commit("shared", files: ["a.txt": "2"])
        }
        defer { repo.remove() }
        try await repo.gitAsync("remote", "add", "origin", remote.url.path)
        try await repo.gitAsync("push", "-q", "-u", "origin", "main")
        // One commit only on the remote side, two only locally.
        try await repo.gitAsync("reset", "-q", "--hard", "HEAD~1")
        try await repo.gitAsync("commit", "-q", "--allow-empty", "-m", "local one")
        try await repo.gitAsync("commit", "-q", "--allow-empty", "-m", "local two")

        let refs = try await repo.cli.refs()
        let main = try #require(refs.first { $0.isLocalBranch && $0.name == "main" })
        #expect(main.upstream == "origin/main")
        #expect(main.ahead == 2)
        #expect(main.behind == 1)
        #expect(main.subject == "local two")
        #expect(main.date != nil)
        let remoteMain = try #require(refs.first { $0.isRemoteBranch })
        #expect(remoteMain.subject == "shared")
    }

    @Test("A branch without upstream has no counts")
    func noUpstream() async throws {
        let repo = try await GitTestRepo.make { try $0.commit("base", files: ["a.txt": "1"]) }
        defer { repo.remove() }
        let main = try #require(try await repo.cli.refs().first { $0.name == "main" })
        #expect(main.upstream == nil)
        #expect(main.ahead == nil && main.behind == nil)
        #expect(main.subject == "base")
    }
}
