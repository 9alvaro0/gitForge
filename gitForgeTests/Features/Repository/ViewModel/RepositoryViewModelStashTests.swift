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
}
