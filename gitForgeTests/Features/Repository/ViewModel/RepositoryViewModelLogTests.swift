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
        let scope = vm.history.graphScope()
        #expect(scope == ["HEAD", "refs/heads/feature/a", "refs/heads/feature/b", "--tags", "stashA"])
    }

    @Test("A loaded page drops each stash's parent[1] and parent[2] but keeps parent[0]")
    func dropStashInternalsRemovesIndexAndUntrackedTrees() {
        let vm = Self.makeVM()
        // Stash commit has 3 parents: real HEAD, index tree, untracked tree.
        let stashSha = "stash-1"
        let realParent = "real-head"
        let indexParent = "index-tree"
        let untrackedParent = "untracked-tree"
        vm.stashes = [Stash(index: 0, sha: stashSha, subject: "WIP")]
        vm.history.replaceLog(with: [
            Self.commit(stashSha, parents: [realParent, indexParent, untrackedParent]),
            Self.commit(realParent),
            Self.commit(indexParent),
            Self.commit(untrackedParent),
            Self.commit("unrelated"),
        ])
        let surviving = Set(vm.history.commits.map(\.sha))
        #expect(surviving == [stashSha, realParent, "unrelated"])
        #expect(vm.history.loadedRawCount == 5)
    }

    @Test("A loaded page keeps every commit when there are no stashes")
    func dropStashInternalsNoOpWithoutStashes() {
        let vm = Self.makeVM()
        vm.stashes = []
        vm.history.replaceLog(with: [Self.commit("a"), Self.commit("b")])
        #expect(vm.history.commits.map(\.sha) == ["a", "b"])
    }

    @Test("loadInitial is a no-op when commits already populated")
    func loadInitialNoOpWhenCommitsExist() async {
        let vm = Self.makeVM()
        vm.history.commits = [Self.commit("aaa")]
        let beforeGen = vm.history.logGen
        await vm.history.loadInitial()
        #expect(vm.history.logGen == beforeGen, "should not bump the token on early-return")
        #expect(vm.history.commits.count == 1)
    }

    @Test("loadMoreIfNeeded is a no-op when hasMore is false")
    func loadMoreNoOpWhenNoMore() async {
        let vm = Self.makeVM()
        vm.history.hasMore = false
        let beforeGen = vm.history.logGen
        await vm.history.loadMoreIfNeeded(currentItem: Self.commit("aaa"))
        #expect(vm.history.logGen == beforeGen)
    }

    @Test("loadMoreIfNeeded is a no-op when item isn't the current last")
    func loadMoreNoOpWhenItemIsNotLast() async {
        let vm = Self.makeVM()
        vm.history.commits = [Self.commit("aaa"), Self.commit("bbb")]
        vm.history.hasMore = true
        let beforeGen = vm.history.logGen
        // Caller asks to load more "after aaa" but the last is bbb — refuse.
        await vm.history.loadMoreIfNeeded(currentItem: Self.commit("aaa"))
        #expect(vm.history.logGen == beforeGen)
    }
}
