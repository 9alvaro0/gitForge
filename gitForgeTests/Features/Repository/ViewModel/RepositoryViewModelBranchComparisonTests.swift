import Foundation
import Testing
@testable import gitForge

@Suite("RepositoryViewModel — branch vs trunk and pushing any branch", .serialized)
@MainActor
struct RepositoryViewModelBranchComparisonTests {

    private func localRef(_ name: String, in vm: RepositoryViewModel) throws -> GitRef {
        try #require(vm.localBranches.first { $0.name == name })
    }

    @Test("Ahead / behind main and the commits main doesn't have")
    func comparesWithMain() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("base", files: ["f.txt": "0\n"])
            try repo.git("checkout", "-q", "-b", "feature")
            try repo.commit("feature one", files: ["a.txt": "1\n"])
            try repo.commit("feature two", files: ["a.txt": "2\n"])
            try repo.git("checkout", "-q", "main")
            try repo.commit("main only", files: ["f.txt": "1\n"])
            try repo.git("tag", "v1")
        }
        defer { repo.remove() }
        let vm = RepositoryViewModel(repository: Repository(url: repo.url))
        await vm.loadRefs()

        let comparison = try #require(await vm.comparison(of: try localRef("feature", in: vm)))
        #expect(comparison.trunk == "main")
        #expect(comparison.ahead == 2)
        #expect(comparison.behind == 1)
        #expect(comparison.commitsNotInTrunk.map(\.subject) == ["feature two", "feature one"])

        #expect(await vm.comparison(of: try localRef("main", in: vm)) == nil)
        let tag = try #require(vm.tags.first)
        #expect(await vm.comparison(of: tag) == nil)
    }

    @Test("Falls back to master, and to nothing without a trunk")
    func trunkFallback() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("base", files: ["f.txt": "0\n"])
            try repo.git("branch", "-m", "master")
            try repo.git("branch", "topic")
        }
        defer { repo.remove() }
        let vm = RepositoryViewModel(repository: Repository(url: repo.url))
        await vm.loadRefs()
        #expect(vm.trunkBranch?.name == "master")

        try repo.git("branch", "-m", "master", "trunk")
        await vm.loadRefs()
        #expect(vm.trunkBranch == nil)
        #expect(await vm.comparison(of: try localRef("topic", in: vm)) == nil)
    }

    @Test("Pushes a branch that isn't checked out and sets its upstream")
    func pushesOtherBranch() async throws {
        let remote = try GitTestRepo(bare: true)
        let repo = try GitTestRepo()
        defer { remote.remove(); repo.remove() }
        try repo.commit("base", files: ["f.txt": "0\n"])
        try repo.git("remote", "add", "origin", remote.url.path(percentEncoded: false))
        try repo.git("branch", "feature")
        let vm = RepositoryViewModel(repository: Repository(url: repo.url))
        await vm.loadRefs()

        #expect(await vm.pushBranch(try localRef("feature", in: vm)))
        #expect(vm.remoteFailure == nil)
        #expect(try remote.git("branch", "--list", "feature").contains("feature"))
        #expect(try repo.git("config", "--get", "branch.feature.merge")
            .trimmingCharacters(in: .whitespacesAndNewlines) == "refs/heads/feature")
        #expect(try localRef("feature", in: vm).upstream == "origin/feature")
    }

    @Test("A tracked branch goes to its upstream, even under another name")
    func pushesToTrackedName() async throws {
        let remote = try GitTestRepo(bare: true)
        let repo = try GitTestRepo()
        defer { remote.remove(); repo.remove() }
        try repo.commit("base", files: ["f.txt": "0\n"])
        try repo.git("remote", "add", "origin", remote.url.path(percentEncoded: false))
        try repo.git("push", "-q", "origin", "main:remote-name")
        try repo.git("fetch", "-q", "origin")
        try repo.git("branch", "--track", "local-name", "origin/remote-name")
        try repo.git("checkout", "-q", "local-name")
        try repo.commit("more", files: ["f.txt": "1\n"])
        try repo.git("checkout", "-q", "main")
        let vm = RepositoryViewModel(repository: Repository(url: repo.url))
        await vm.loadRefs()

        #expect(await vm.pushBranch(try localRef("local-name", in: vm)))
        let local = try repo.git("rev-parse", "local-name")
        #expect(try remote.git("rev-parse", "remote-name") == local)
        #expect(try remote.git("branch", "--list", "local-name").isEmpty)
    }
}
