import Foundation
import Testing
@testable import gitForge

@Suite("RepositoryViewModel — batch selection in staging")
@MainActor
struct RepositoryViewModelStagingSelectionTests {

    private static func makeVM() -> RepositoryViewModel {
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        return RepositoryViewModel(repository: Repository(url: url))
    }

    private static func file(_ path: String,
                             staged: WorkingCopyFile.Status = .unmodified,
                             unstaged: WorkingCopyFile.Status = .modified) -> WorkingCopyFile {
        WorkingCopyFile(path: path, stagedStatus: staged, unstagedStatus: unstaged, originalPath: nil)
    }

    @Test("toggleSelection adds when absent, removes when present")
    func toggleAddsAndRemoves() {
        let vm = Self.makeVM()
        let f = Self.file("a.txt")
        vm.workingCopy.toggleSelection(f)
        #expect(vm.workingCopy.selectedFilePaths.contains("a.txt"))
        vm.workingCopy.toggleSelection(f)
        #expect(vm.workingCopy.selectedFilePaths.contains("a.txt") == false)
    }

    @Test("deselect drops only the requested paths")
    func deselectDropsOnlyRequested() {
        let vm = Self.makeVM()
        vm.workingCopy.selectedFilePaths = ["a.txt", "b.txt", "c.txt"]
        vm.workingCopy.deselect([Self.file("a.txt"), Self.file("c.txt")])
        #expect(vm.workingCopy.selectedFilePaths == ["b.txt"])
    }

    @Test("stageSelected ignores selected files that are already staged")
    func stageSelectedOnlyConsidersUnstaged() async {
        let vm = Self.makeVM()
        // a.txt is already staged; b.txt is unstaged. Both are ticked.
        vm.workingCopy.status = WorkingCopyStatus(files: [
            Self.file("a.txt", staged: .modified, unstaged: .unmodified),
            Self.file("b.txt", staged: .unmodified, unstaged: .modified),
        ])
        vm.workingCopy.selectedFilePaths = ["a.txt", "b.txt"]
        // Running over a bogus working dir means stage() will throw, but
        // the precondition we care about is the filter. After the call,
        // b.txt should have been deselected (it was the target), a.txt
        // should still be ticked because stageSelected wouldn't have
        // touched it… BUT runStageOperation swallows the throw via
        // commitError so the deselect runs unconditionally. Asserting only
        // the filter semantics: a is still ticked, b was attempted and so
        // was dropped from selection.
        await vm.stageSelected()
        #expect(vm.workingCopy.selectedFilePaths.contains("a.txt"), "already-staged file shouldn't be cleared")
        #expect(vm.workingCopy.selectedFilePaths.contains("b.txt") == false, "target file should be cleared after batch")
    }

    @Test("A partially staged file counts as both unstaged and staged")
    func partiallyStagedIsOnBothSides() {
        let vm = Self.makeVM()
        // a.txt has changes on both sides, so it's listed under Unstaged too.
        vm.workingCopy.status = WorkingCopyStatus(files: [
            Self.file("a.txt", staged: .modified, unstaged: .modified),
            Self.file("b.txt", staged: .modified, unstaged: .unmodified),
        ])
        vm.workingCopy.selectedFilePaths = ["a.txt", "b.txt"]
        #expect(vm.workingCopy.selectedUnstagedFiles.map(\.path) == ["a.txt"])
        #expect(vm.workingCopy.selectedStagedFiles.map(\.path) == ["a.txt", "b.txt"])
    }

    @Test("A conflicted file is listed once, under Unstaged")
    func conflictedIsNotStaged() {
        let conflicted = Self.file("c.txt", staged: .unmerged, unstaged: .unmerged)
        #expect(!conflicted.isStaged)
        #expect(conflicted.isUnstaged)
        let status = WorkingCopyStatus(files: [conflicted, Self.file("a.txt", staged: .modified, unstaged: .unmodified)])
        #expect(status.stagedFiles.map(\.path) == ["a.txt"])
        #expect(status.unstagedFiles.map(\.path) == ["c.txt"])
    }

    @Test("unstageSelected ignores selected files that are not staged")
    func unstageSelectedOnlyConsidersStaged() async {
        let vm = Self.makeVM()
        vm.workingCopy.status = WorkingCopyStatus(files: [
            Self.file("a.txt", staged: .modified, unstaged: .unmodified),
            Self.file("b.txt", staged: .unmodified, unstaged: .modified),
        ])
        vm.workingCopy.selectedFilePaths = ["a.txt", "b.txt"]
        await vm.unstageSelected()
        #expect(vm.workingCopy.selectedFilePaths.contains("a.txt") == false, "target staged file should be cleared")
        #expect(vm.workingCopy.selectedFilePaths.contains("b.txt"), "unstaged file shouldn't be touched")
    }

    @Test("stageSelected with no matching files is a no-op")
    func stageSelectedEmptyIsNoOp() async {
        let vm = Self.makeVM()
        vm.workingCopy.status = WorkingCopyStatus(files: [
            Self.file("a.txt", staged: .modified, unstaged: .unmodified),
        ])
        // Only the staged file is selected — nothing to stage.
        vm.workingCopy.selectedFilePaths = ["a.txt"]
        await vm.stageSelected()
        // Selection unchanged because nothing was attempted.
        #expect(vm.workingCopy.selectedFilePaths == ["a.txt"])
    }
}
