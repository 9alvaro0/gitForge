import Foundation
import Testing
@testable import gitForge

@Suite("RepositoryViewModel — refs loader", .serialized)
@MainActor
struct RepositoryViewModelRefsTests {

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
