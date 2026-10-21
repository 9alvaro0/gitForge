import Foundation
import Testing
@testable import gitForge

@Suite("RepositoryViewModel — discard what blocks a pull", .serialized)
@MainActor
struct RepositoryViewModelPullDiscardTests {

    /// `origin` (bare), `writer` who pushes to it, and `local` — the repo
    /// under test — tracking `origin/main` one commit behind `writer`.
    /// `local` pins the pull settings a personal global config could flip.
    private struct Repos {
        let origin: GitTestRepo
        let writer: GitTestRepo
        let local: GitTestRepo

        func remove() {
            origin.remove()
            writer.remove()
            local.remove()
        }
    }

    private static func makeRepos(base: [String: String], incoming: [String: String]) async throws -> Repos {
        let origin = try await GitTestRepo.make(bare: true)
        let writer = try await GitTestRepo.make { repo in
            try repo.commit("base", files: base)
            try repo.git("remote", "add", "origin", origin.url.path)
            try repo.git("push", "-q", "-u", "origin", "main")
        }
        let local = try await GitTestRepo.make { repo in
            try repo.git("config", "pull.rebase", "false")
            try repo.git("config", "pull.ff", "true")
            try repo.git("config", "rebase.autoStash", "false")
            try repo.git("config", "merge.autoStash", "false")
            try repo.git("remote", "add", "origin", origin.url.path)
            try repo.git("fetch", "-q", "origin")
            try repo.git("reset", "-q", "--hard", "origin/main")
            try repo.git("branch", "-q", "--set-upstream-to=origin/main")
        }
        let pushed: Result<Void, Error> = await GitProcess.offPool {
            Result {
                try writer.commit("incoming", files: incoming)
                try writer.git("push", "-q", "origin", "main")
            }
        }
        try pushed.get()
        return Repos(origin: origin, writer: writer, local: local)
    }

    private static func makeVM(_ repo: GitTestRepo) async -> RepositoryViewModel {
        let vm = RepositoryViewModel(repository: Repository(url: repo.url))
        await vm.loadRefs()
        return vm
    }

    @Test("A pull blocked by local changes asks to discard exactly the files in the way")
    func blockedPullAsks() async throws {
        let repos = try await Self.makeRepos(
            base: ["a.txt": "a\n", "staged.txt": "s\n", "keep.txt": "keep\n"],
            incoming: ["a.txt": "a2\n", "staged.txt": "s2\n", "n.txt": "theirs\n"])
        defer { repos.remove() }
        try await repos.local.externalWriteAsync("local\n", to: "a.txt")
        try await repos.local.externalWriteAsync("staged-local\n", to: "staged.txt")
        try await repos.local.gitAsync("add", "staged.txt")
        try await repos.local.externalWriteAsync("mine\n", to: "n.txt")
        try await repos.local.externalWriteAsync("keep-local\n", to: "keep.txt")
        let vm = await Self.makeVM(repos.local)

        #expect(await vm.pull(ffOnly: true) == false)

        #expect(vm.remoteFailure == nil, "the question replaces the error toast")
        let request = try #require(vm.pullDiscardRequest)
        #expect(request.files.map(\.path).sorted() == ["a.txt", "n.txt", "staged.txt"])
        #expect(request.refusedByRebase == false)
        #expect(request.rebase == false)
        #expect(request.ffOnly == true)
    }

    @Test("Confirming discards only those files, runs the same pull and keeps the other changes")
    func confirmDiscardsAndPulls() async throws {
        let repos = try await Self.makeRepos(
            base: ["a.txt": "a\n", "staged.txt": "s\n", "keep.txt": "keep\n"],
            incoming: ["a.txt": "a2\n", "staged.txt": "s2\n", "n.txt": "theirs\n"])
        defer { repos.remove() }
        try await repos.local.externalWriteAsync("local\n", to: "a.txt")
        try await repos.local.externalWriteAsync("staged-local\n", to: "staged.txt")
        try await repos.local.gitAsync("add", "staged.txt")
        try await repos.local.externalWriteAsync("mine\n", to: "n.txt")
        try await repos.local.externalWriteAsync("keep-local\n", to: "keep.txt")
        let vm = await Self.makeVM(repos.local)
        await vm.pull(ffOnly: true)
        let request = try #require(vm.pullDiscardRequest)

        #expect(await vm.discardBlockingChangesAndPull(request))

        #expect(vm.pullDiscardRequest == nil)
        #expect(vm.remoteFailure == nil)
        #expect(vm.operationSuccess?.message == "Pulled from origin/main")
        #expect(repos.local.read("a.txt") == "a2\n")
        #expect(repos.local.read("staged.txt") == "s2\n")
        #expect(repos.local.read("n.txt") == "theirs\n")
        #expect(try repos.local.porcelain() == [" M keep.txt"], "a change that wasn't in the way survives")
    }

    @Test("A staged new file that collides with an incoming one is discarded too")
    func stagedNewFile() async throws {
        let repos = try await Self.makeRepos(base: ["a.txt": "a\n"], incoming: ["added.txt": "theirs\n"])
        defer { repos.remove() }
        try await repos.local.externalWriteAsync("mine\n", to: "added.txt")
        try await repos.local.gitAsync("add", "added.txt")
        let vm = await Self.makeVM(repos.local)
        await vm.pull(ffOnly: true)
        let request = try #require(vm.pullDiscardRequest)
        #expect(request.files.map(\.path) == ["added.txt"])

        #expect(await vm.discardBlockingChangesAndPull(request))

        #expect(repos.local.read("added.txt") == "theirs\n")
        #expect(try repos.local.porcelain().isEmpty)
    }

    @Test("A rebase pull blocked by local changes lists every tracked change, not untracked files")
    func rebaseListsTrackedChanges() async throws {
        let repos = try await Self.makeRepos(
            base: ["a.txt": "a\n", "keep.txt": "keep\n", "staged.txt": "s\n"],
            incoming: ["a.txt": "a2\n"])
        defer { repos.remove() }
        try await repos.local.externalWriteAsync("keep-local\n", to: "keep.txt")
        try await repos.local.externalWriteAsync("staged-local\n", to: "staged.txt")
        try await repos.local.gitAsync("add", "staged.txt")
        try await repos.local.externalWriteAsync("scratch\n", to: "untracked.txt")
        let vm = await Self.makeVM(repos.local)

        #expect(await vm.pull(rebase: true) == false)

        #expect(vm.remoteFailure == nil)
        let request = try #require(vm.pullDiscardRequest)
        #expect(request.files.map(\.path).sorted() == ["keep.txt", "staged.txt"])
        #expect(request.refusedByRebase)
        #expect(request.rebase == true)

        #expect(await vm.discardBlockingChangesAndPull(request))

        #expect(repos.local.read("a.txt") == "a2\n")
        #expect(repos.local.read("keep.txt") == "keep\n")
        #expect(try repos.local.porcelain() == ["?? untracked.txt"], "untracked files never blocked the rebase")
    }

    @Test("With pull.rebase set, a plain pull refused by the rebase is told apart and pulled the same way again")
    func configuredRebase() async throws {
        let repos = try await Self.makeRepos(base: ["a.txt": "a\n", "keep.txt": "keep\n"],
                                             incoming: ["a.txt": "a2\n"])
        defer { repos.remove() }
        try await repos.local.gitAsync("config", "pull.rebase", "true")
        try await repos.local.gitAsync("commit", "-q", "--allow-empty", "-m", "local only")
        try await repos.local.externalWriteAsync("keep-local\n", to: "keep.txt")
        let vm = await Self.makeVM(repos.local)

        #expect(await vm.pull() == false)

        let request = try #require(vm.pullDiscardRequest)
        #expect(request.files.map(\.path) == ["keep.txt"])
        #expect(request.refusedByRebase)
        #expect(request.rebase == false, "the retry repeats the plain pull, which the config rebases")

        #expect(await vm.discardBlockingChangesAndPull(request))

        #expect(repos.local.read("a.txt") == "a2\n")
        let subjects = try await repos.local.gitAsync("log", "--format=%s")
        #expect(subjects == "local only\nincoming\nbase\n", "rebased, not merged")
    }

    @Test("A pull that fails for another reason still reports the failure and asks nothing")
    func otherFailureStillReports() async {
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        let vm = RepositoryViewModel(repository: Repository(url: url))

        #expect(await vm.pull() == false)

        #expect(vm.remoteFailure != nil)
        #expect(vm.pullDiscardRequest == nil)
    }

    @Test("Confirming is refused while another remote operation runs")
    func confirmGuard() async throws {
        let repos = try await Self.makeRepos(base: ["a.txt": "a\n"], incoming: ["a.txt": "a2\n"])
        defer { repos.remove() }
        try await repos.local.externalWriteAsync("local\n", to: "a.txt")
        let vm = await Self.makeVM(repos.local)
        await vm.pull(ffOnly: true)
        let request = try #require(vm.pullDiscardRequest)
        vm.remoteOperation = .fetching

        #expect(await vm.discardBlockingChangesAndPull(request) == false)

        #expect(repos.local.read("a.txt") == "local\n", "nothing is discarded")
    }
}
