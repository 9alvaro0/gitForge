import Foundation
import Testing
@testable import gitForge

@Suite("RepositoryViewModel — refs loader", .serialized)
@MainActor
struct RepositoryViewModelRefsLoaderTests {

    private static func makeVM() -> RepositoryViewModel {
        // Bogus working dir → every cli call throws on the first guard, so
        // the four `try?` reads inside loadRefs all produce nil and the
        // `if let` writes are skipped. This lets us exercise the gen-token
        // bookkeeping without a fake CLI.
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        return RepositoryViewModel(repository: Repository(url: url))
    }

    @Test("loadRefs bumps refsGen by one")
    func loadRefsBumpsGen() async {
        let vm = Self.makeVM()
        let before = vm.refsGen
        await vm.loadRefs()
        #expect(vm.refsGen == before &+ 1)
    }

    @Test("loadRefs leaves pre-seeded state untouched when every CLI read fails")
    func loadRefsPreservesStateOnFailure() async {
        let vm = Self.makeVM()
        // Pre-seed values that loadRefs would happily overwrite if the CLI
        // returned anything. Bogus dir guarantees every `try?` is nil and the
        // `if let` blocks are skipped — sentinel values must survive.
        let sentinelRef = GitRef(
            name: "main",
            kind: .localBranch,
            targetSha: "deadbeef",
            isHead: true
        )
        vm.refs = [sentinelRef]
        vm.currentBranchName = "main"
        vm.stashes = [Stash(index: 0, sha: "stash-1", subject: "WIP")]
        vm.unmergedLocalBranchRefs = ["refs/heads/feature/x"]

        await vm.loadRefs()

        #expect(vm.refs == [sentinelRef])
        #expect(vm.currentBranchName == "main")
        #expect(vm.stashes.count == 1)
        #expect(vm.unmergedLocalBranchRefs == ["refs/heads/feature/x"])
    }

    @Test("two consecutive loadRefs calls move the token monotonically")
    func loadRefsTokenIsMonotonic() async {
        let vm = Self.makeVM()
        await vm.loadRefs()
        let mid = vm.refsGen
        await vm.loadRefs()
        #expect(vm.refsGen == mid &+ 1)
    }
}

@Suite("RepositoryViewModel — HEAD's branch from disk", .serialized)
@MainActor
struct RepositoryViewModelHeadBranchTests {

    @Test("A detached checkout made outside the app clears the current branch")
    func externalDetachClearsCurrentBranch() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("first", files: ["a.txt": "1"])
            try repo.commit("second", files: ["a.txt": "2"])
        }
        defer { repo.remove() }
        let vm = RepositoryViewModel(repository: Repository(url: repo.url))
        await vm.loadRefs()
        #expect(vm.currentBranchName == "main")

        let first = try await repo.gitAsync("rev-parse", "HEAD~1").trimmingCharacters(in: .whitespacesAndNewlines)
        try await repo.gitAsync("checkout", "-q", "--detach", first)
        await vm.refreshFromExternalChange()

        #expect(vm.currentBranchName == nil)
        #expect(vm.headSha == first)
        // Chips mark HEAD's branch by name; `isHead` comes from for-each-ref.
        #expect(!vm.localBranches.contains { $0.name == vm.currentBranchName || $0.isHead })
    }

    @Test("Detaching on the branch's own tip still clears the current branch")
    func externalDetachAtSameCommitClearsCurrentBranch() async throws {
        let repo = try await GitTestRepo.make { try $0.commit("first", files: ["a.txt": "1"]) }
        defer { repo.remove() }
        let vm = RepositoryViewModel(repository: Repository(url: repo.url))
        await vm.loadRefs()
        let tip = vm.headSha
        #expect(vm.currentBranchName == "main")

        try await repo.gitAsync("checkout", "-q", "--detach")
        await vm.refreshFromExternalChange()

        #expect(vm.currentBranchName == nil)
        #expect(vm.headSha == tip)
    }

    @Test("Checking out a commit from the app clears the current branch")
    func checkoutCommitClearsCurrentBranch() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("first", files: ["a.txt": "1"])
            try repo.commit("second", files: ["a.txt": "2"])
        }
        defer { repo.remove() }
        let vm = RepositoryViewModel(repository: Repository(url: repo.url))
        await vm.loadRefs()
        #expect(vm.currentBranchName == "main")

        let first = try await repo.gitAsync("rev-parse", "HEAD~1").trimmingCharacters(in: .whitespacesAndNewlines)
        guard case .success = await vm.checkoutCommit(first) else {
            Issue.record("checkoutCommit failed"); return
        }

        #expect(vm.currentBranchName == nil)
        #expect(vm.headSha == first)
    }
}

@Suite("RepositoryViewModel — derived ref lists")
@MainActor
struct RepositoryViewModelRefListsTests {

    @Test("Branch and tag lists are split by kind and sorted when refs change")
    func listsFollowRefs() {
        let vm = RepositoryViewModel(repository: Repository(url: URL(fileURLWithPath: "/var/empty")))
        vm.refs = [
            GitRef(name: "zeta", kind: .localBranch, targetSha: "1", isHead: false),
            GitRef(name: "v2", kind: .tag, targetSha: "2", isHead: false),
            GitRef(name: "origin/main", kind: .remoteBranch(remote: "origin"), targetSha: "3", isHead: false),
            GitRef(name: "alpha", kind: .localBranch, targetSha: "4", isHead: true),
            GitRef(name: "v1", kind: .tag, targetSha: "5", isHead: false),
        ]
        #expect(vm.localBranches.map(\.name) == ["alpha", "zeta"])
        #expect(vm.remoteBranches.map(\.name) == ["origin/main"])
        #expect(vm.tags.map(\.name) == ["v1", "v2"])

        vm.refs = []
        #expect(vm.localBranches.isEmpty && vm.remoteBranches.isEmpty && vm.tags.isEmpty)
    }
}

@Suite("RepositoryViewModel — manual refresh", .serialized)
@MainActor
struct RepositoryViewModelManualRefreshTests {

    private static func makeVM() -> RepositoryViewModel {
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        return RepositoryViewModel(repository: Repository(url: url))
    }

    @Test("refresh runs the parallel cluster without crashing on a bogus dir")
    func refreshSmoke() async {
        let vm = Self.makeVM()
        // Smoke test: refresh kicks off log + refs + status + conflicts +
        // identity in parallel. On a bogus dir every leg short-circuits
        // through its own error handling. This test just guards that the
        // cluster shape stays correct (no missing await, no deadlock).
        await vm.refresh()
        // refsGen and identityGen each bump exactly once per refresh.
        #expect(vm.refsGen >= 1)
        #expect(vm.identityGen >= 1)
        // Identity write goes through even on bogus dir (currentIdentity
        // returns the all-nil sentinel rather than throwing).
        #expect(vm.repoIdentity != nil)
    }
}
