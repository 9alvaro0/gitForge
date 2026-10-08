import Foundation
import Testing
@testable import gitForge

@Suite("RepositoryViewModel — stash guards", .serialized)
@MainActor
struct RepositoryViewModelStashTests {

    private static func makeVM() -> RepositoryViewModel {
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        return RepositoryViewModel(repository: Repository(url: url))
    }

    @Test("stashAll fails with .nothingToStash when the working tree is clean")
    func stashAllNothingToStash() async {
        let vm = Self.makeVM()
        // Default `status` has no files → `isClean == true`. The guard fires
        // before touching the cli, so a bogus working dir is fine here.
        let result = await vm.stashAll()
        guard case .failure(let error) = result else {
            Issue.record("Expected .failure for a clean working tree")
            return
        }
        guard let stashError = error as? StashError, case .nothingToStash = stashError else {
            Issue.record("Expected StashError.nothingToStash, got \(error)")
            return
        }
    }

    @Test("StashError.nothingToStash carries a non-empty user-facing description")
    func stashErrorDescription() {
        let message = StashError.nothingToStash.errorDescription
        #expect(message?.isEmpty == false)
    }

    @Test("dropStash returns .failure on a bogus working dir without crashing")
    func dropStashSurfacesFailure() async {
        let vm = Self.makeVM()
        let stash = Stash(index: 0, sha: "deadbeef", subject: "WIP")
        let result = await vm.dropStash(stash)
        guard case .failure = result else {
            Issue.record("Expected .failure for a bogus working dir")
            return
        }
    }

    @Test("applyStash returns .failed on a bogus working dir without crashing")
    func applyStashSurfacesFailure() async {
        let vm = Self.makeVM()
        let stash = Stash(index: 0, sha: "deadbeef", subject: "WIP")
        let outcome = await vm.applyStash(stash, drop: false)
        // Bogus dir → cli.stashApply throws GitError.invalidWorkingDirectory,
        // catch fires, refreshAfterIntegration also no-ops on bogus dir, so
        // mergeState stays `.clean` and we end on `.failed`.
        guard case .failed = outcome else {
            Issue.record("Expected .failed, got \(outcome)")
            return
        }
    }

    @Test("A conflicted apply remembers the stash and abort keeps unrelated work")
    func conflictedApplyThenAbort() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("init", files: ["conf.txt": "base\n", "mine.txt": "m\n"])
            try repo.write("from-stash\n", to: "conf.txt")
            try repo.git("stash", "push", "-q")
            try repo.commit("conflicting", files: ["conf.txt": "from-head\n"])
            try repo.write("my work\n", to: "mine.txt")
        }
        defer { repo.remove() }

        let vm = RepositoryViewModel(repository: Repository(url: repo.url))
        let stash = try #require(try await repo.cli.stashes().first)

        #expect(await vm.applyStash(stash, drop: false) == .conflicts)
        #expect(vm.conflictedStashSha == stash.sha)

        guard case .success = await vm.abortStashApply() else {
            Issue.record("abortStashApply failed")
            return
        }
        #expect(vm.conflictedStashSha == nil)
        #expect(vm.mergeState == .clean)
        #expect(repo.read("mine.txt") == "my work\n")
        #expect(repo.read("conf.txt") == "from-head\n")
    }
}
