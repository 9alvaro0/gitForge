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

    /// A repo with one commit pushed to a bare `origin` as `main`. Push only: a fetch would
    /// create `origin/HEAD` on its own (git 2.48 and later).
    private static func pushedRepo() async throws -> (repo: GitTestRepo, remote: GitTestRepo) {
        let remote = try await GitTestRepo.make(bare: true)
        let repo = try await GitTestRepo.make { try $0.commit("base", files: ["a.txt": "1"]) }
        try await repo.gitAsync("remote", "add", "origin", remote.url.path)
        try await repo.gitAsync("push", "-q", "-u", "origin", "main")
        return (repo, remote)
    }

    @Test("Without tags, the refs are the same branches with the same tracking, and no tag")
    func refsWithoutTags() async throws {
        let (repo, remote) = try await Self.pushedRepo()
        defer { repo.remove(); remote.remove() }
        try await repo.gitAsync("commit", "-q", "--allow-empty", "-m", "local one")
        try await repo.gitAsync("branch", "-q", "topic")
        try await repo.gitAsync("tag", "v1")
        try await repo.gitAsync("tag", "-a", "v2", "-m", "Release")

        let all = try await repo.cli.refs()
        let branches = try await repo.cli.refs(includingTags: false)
        #expect(all.filter(\.isTag).count == 2)
        #expect(!branches.contains { $0.isTag })
        #expect(branches == all.filter { !$0.isTag })
        let main = try #require(branches.first { $0.isLocalBranch && $0.name == "main" })
        #expect(main.upstream == "origin/main" && main.ahead == 1 && main.behind == 0)
        #expect(branches.contains { $0.isRemoteBranch && $0.name == "origin/main" })
    }

    @Test("remoteHeads names the branch each remote's HEAD points at")
    func remoteHeads() async throws {
        let (repo, remote) = try await Self.pushedRepo()
        defer { repo.remove(); remote.remove() }
        try await repo.gitAsync("remote", "set-head", "origin", "main")
        #expect(try await repo.cli.remoteHeads() == ["origin": "origin/main"])
    }

    @Test("A remote without a HEAD is left out")
    func remoteWithoutHead() async throws {
        let (repo, remote) = try await Self.pushedRepo()
        defer { repo.remove(); remote.remove() }
        #expect(try await repo.cli.remoteHeads().isEmpty)
    }

    @Test("remoteHeads parses symrefs only")
    func parseRemoteHeads() {
        let stdout = "refs/remotes/origin/HEAD\trefs/remotes/origin/main\nrefs/remotes/origin/main\t\n"
        #expect(GitCLI.parseRemoteHeads(stdout) == ["origin": "origin/main"])
    }
}
