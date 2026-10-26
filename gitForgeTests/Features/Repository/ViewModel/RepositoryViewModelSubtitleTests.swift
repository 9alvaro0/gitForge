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
        #expect(vm.toolbarSubtitle(for: .history, pullsTab: .team) == "main  ↑2")
        #expect(vm.toolbarSubtitle(for: .branches, pullsTab: .team) == "main  ↑2")
    }

    @Test("Changes adds the staged and unstaged counts the status bar used to show")
    func changesSubtitle() {
        let vm = Self.makeVM()
        vm.workingCopy.status = WorkingCopyStatus(files: [
            WorkingCopyFile(path: "a", stagedStatus: .modified, unstagedStatus: .unmodified, originalPath: nil),
            WorkingCopyFile(path: "b", stagedStatus: .unmodified, unstagedStatus: .modified, originalPath: nil),
            WorkingCopyFile(path: "c", stagedStatus: .unmodified, unstagedStatus: .untracked, originalPath: nil),
        ])
        #expect(vm.toolbarSubtitle(for: .changes, pullsTab: .team) == "main · 2 unstaged, 1 staged")
    }

    @Test("A clean working copy says so on Changes")
    func changesClean() {
        let vm = Self.makeVM()
        vm.workingCopy.status = WorkingCopyStatus(files: [])
        #expect(vm.toolbarSubtitle(for: .changes, pullsTab: .team) == "main · no changes")
    }

    @Test("Open and Closed show the host, or that none is connected", arguments: [PullsTab.open, .closed])
    func pullsSubtitle(tab: PullsTab) {
        #expect(Self.makeVM().toolbarSubtitle(for: .pulls, pullsTab: tab) == "not connected")
    }

    @Test("Team and Mine show no branch nor host: the inbox belongs to no repository", arguments: [PullsTab.team, .mine])
    func pullsInboxSubtitle(tab: PullsTab) {
        let vm = Self.makeVM()
        vm.aheadCount = 2
        #expect(vm.toolbarSubtitle(for: .pulls, pullsTab: tab) == "")
    }

    @Test("The tab of Pull requests changes no other section's subtitle")
    func otherSectionsIgnoreTheTab() {
        let vm = Self.makeVM()
        vm.aheadCount = 2
        #expect(vm.toolbarSubtitle(for: .history, pullsTab: .open) == "main  ↑2")
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
        #expect(vm.toolbarSubtitle(for: .conflict, pullsTab: .team) == expected)
    }

    @Test("Conflicts with nothing in progress fall back to the branch")
    func conflictClean() {
        #expect(Self.makeVM().toolbarSubtitle(for: .conflict, pullsTab: .team) == "main")
    }
}
