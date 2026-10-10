import Foundation
import Testing
@testable import gitForge

@Suite("RepositoryViewModel — toolbar subtitle", .serialized)
@MainActor
struct RepositoryViewModelSubtitleTests {

    private static func makeVM(branch: String? = "main") -> RepositoryViewModel {
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        let vm = RepositoryViewModel(repository: Repository(url: url))
        vm.currentBranchName = branch
        return vm
    }

    @Test("Most sections show the branch with ahead / behind")
    func branchSubtitle() {
        let vm = Self.makeVM()
        vm.aheadCount = 2
        #expect(vm.toolbarSubtitle(for: .history) == "main  ↑2")
        #expect(vm.toolbarSubtitle(for: .changes) == "main  ↑2")
    }

    @Test("Pull requests show the host, or that none is connected")
    func pullsSubtitle() {
        #expect(Self.makeVM().toolbarSubtitle(for: .pulls) == "not connected")
    }

    @Test("Conflicts describe the operation in progress", arguments: [
        (MergeState.merging, "merging into main"),
        (.rebasing, "rebasing main"),
        (.cherryPicking, "cherry-picking onto main"),
        (.reverting, "reverting on main"),
        (.unmerged, "applying stash on main"),
    ])
    func conflictSubtitle(state: MergeState, expected: String) {
        let vm = Self.makeVM()
        vm.mergeState = state
        #expect(vm.toolbarSubtitle(for: .conflict) == expected)
    }

    @Test("Conflicts with nothing in progress fall back to the branch")
    func conflictClean() {
        #expect(Self.makeVM().toolbarSubtitle(for: .conflict) == "main")
    }
}
