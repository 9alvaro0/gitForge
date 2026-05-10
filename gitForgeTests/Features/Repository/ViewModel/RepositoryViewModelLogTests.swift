import Foundation
import Testing
@testable import gitForge

@Suite("RepositoryViewModel — log helpers", .serialized)
@MainActor
struct RepositoryViewModelLogHelperTests {

    private static func makeVM() -> RepositoryViewModel {
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        return RepositoryViewModel(repository: Repository(url: url))
    }

    private static func commit(_ sha: String, parents: [String] = []) -> Commit {
        Commit(
            sha: sha,
            parentShas: parents,
            authorName: "Test",
            authorEmail: "t@example.com",
            authorDate: .init(timeIntervalSince1970: 0),
            subject: "subject"
        )
    }

    @Test("graphScope returns HEAD first, then unmerged refs, --tags, then stash shas")
    func graphScopeOrdering() {
        let vm = Self.makeVM()
        vm.unmergedLocalBranchRefs = ["refs/heads/feature/a", "refs/heads/feature/b"]
        vm.stashes = [Stash(index: 0, sha: "stashA", subject: "WIP a")]
        let scope = vm.graphScope()
        #expect(scope == ["HEAD", "refs/heads/feature/a", "refs/heads/feature/b", "--tags", "stashA"])
    }

    @Test("dropStashInternals removes parent[1] and parent[2] but keeps parent[0]")
    func dropStashInternalsRemovesIndexAndUntrackedTrees() {
        let vm = Self.makeVM()
        // Stash commit has 3 parents: real HEAD, index tree, untracked tree.
        let stashSha = "stash-1"
        let realParent = "real-head"
        let indexParent = "index-tree"
        let untrackedParent = "untracked-tree"
        vm.stashes = [Stash(index: 0, sha: stashSha, subject: "WIP")]
        vm.commits = [
            Self.commit(stashSha, parents: [realParent, indexParent, untrackedParent]),
            Self.commit(realParent),
            Self.commit(indexParent),
            Self.commit(untrackedParent),
            Self.commit("unrelated"),
        ]
        vm.dropStashInternals()
        let surviving = Set(vm.commits.map(\.sha))
        #expect(surviving == [stashSha, realParent, "unrelated"])
    }

    @Test("dropStashInternals is a no-op when there are no stashes")
    func dropStashInternalsNoOpWithoutStashes() {
        let vm = Self.makeVM()
        vm.stashes = []
        vm.commits = [Self.commit("a"), Self.commit("b")]
        vm.dropStashInternals()
        #expect(vm.commits.map(\.sha) == ["a", "b"])
    }

    @Test("resetLog wipes log state to defaults")
    func resetLogClearsState() {
        let vm = Self.makeVM()
        vm.commits = [Self.commit("aaa")]
        vm.loadedRawCount = 100
        vm.graphMaxLanes = 4
        vm.hasMore = false
        vm.selectedCommitId = "aaa"
        vm.hasLoadedLogForCurrentScope = true

        vm.resetLog()

        #expect(vm.commits.isEmpty)
        #expect(vm.loadedRawCount == 0)
        #expect(vm.graphLayouts.isEmpty)
        #expect(vm.graphMaxLanes == 1)
        #expect(vm.hasMore == true)
        #expect(vm.selectedCommitId == nil)
        #expect(vm.hasLoadedLogForCurrentScope == false)
    }
}

@Suite("RepositoryViewModel — log op guards", .serialized)
@MainActor
struct RepositoryViewModelLogGuardsTests {

    private static func makeVM() -> RepositoryViewModel {
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        return RepositoryViewModel(repository: Repository(url: url))
    }

    private static func commit(_ sha: String) -> Commit {
        Commit(
            sha: sha,
            parentShas: [],
            authorName: "Test",
            authorEmail: "t@example.com",
            authorDate: .init(timeIntervalSince1970: 0),
            subject: "subject"
        )
    }

    @Test("loadInitial is a no-op when commits already populated")
    func loadInitialNoOpWhenCommitsExist() async {
        let vm = Self.makeVM()
        vm.commits = [Self.commit("aaa")]
        let beforeGen = vm.logGen
        await vm.loadInitial()
        #expect(vm.logGen == beforeGen, "should not bump the token on early-return")
        #expect(vm.commits.count == 1)
    }

    @Test("loadMoreIfNeeded is a no-op when hasMore is false")
    func loadMoreNoOpWhenNoMore() async {
        let vm = Self.makeVM()
        vm.hasMore = false
        let beforeGen = vm.logGen
        await vm.loadMoreIfNeeded(currentItem: Self.commit("aaa"))
        #expect(vm.logGen == beforeGen)
    }

    @Test("loadMoreIfNeeded is a no-op when item isn't the current last")
    func loadMoreNoOpWhenItemIsNotLast() async {
        let vm = Self.makeVM()
        vm.commits = [Self.commit("aaa"), Self.commit("bbb")]
        vm.hasMore = true
        let beforeGen = vm.logGen
        // Caller asks to load more "after aaa" but the last is bbb — refuse.
        await vm.loadMoreIfNeeded(currentItem: Self.commit("aaa"))
        #expect(vm.logGen == beforeGen)
    }

    @Test("revealCommit fast-paths when the sha is already in commitsById")
    func revealCommitFastPath() async {
        let vm = Self.makeVM()
        vm.commits = [Self.commit("aaa"), Self.commit("bbb")]
        let beforeGen = vm.logGen
        await vm.revealCommit(sha: "bbb")
        #expect(vm.scrollTargetSha == "bbb")
        #expect(vm.logGen == beforeGen, "fast path shouldn't bump the token")
    }

    @Test("revealCommit short-circuits when sha is missing and hasMore is false")
    func revealCommitNoOpWhenSearchExhausted() async {
        let vm = Self.makeVM()
        vm.commits = [Self.commit("aaa")]
        vm.hasMore = false
        let beforeGen = vm.logGen
        await vm.revealCommit(sha: "missing")
        #expect(vm.scrollTargetSha == nil)
        #expect(vm.logGen == beforeGen)
    }
}
