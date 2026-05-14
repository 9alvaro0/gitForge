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
        vm.toggleSelection(f)
        #expect(vm.selectedFilePaths.contains("a.txt"))
        vm.toggleSelection(f)
        #expect(vm.selectedFilePaths.contains("a.txt") == false)
    }

    @Test("selectAll inserts every path from the input list (preserving prior selection)")
    func selectAllPreservesExisting() {
        let vm = Self.makeVM()
        vm.selectedFilePaths.insert("preexisting.txt")
        vm.selectAll(in: [Self.file("a.txt"), Self.file("b.txt")])
        #expect(vm.selectedFilePaths == ["preexisting.txt", "a.txt", "b.txt"])
    }

    @Test("deselect drops only the requested paths")
    func deselectDropsOnlyRequested() {
        let vm = Self.makeVM()
        vm.selectedFilePaths = ["a.txt", "b.txt", "c.txt"]
        vm.deselect([Self.file("a.txt"), Self.file("c.txt")])
        #expect(vm.selectedFilePaths == ["b.txt"])
    }

    @Test("stageSelected ignores selected files that are already staged")
    func stageSelectedOnlyConsidersUnstaged() async {
        let vm = Self.makeVM()
        // a.txt is already staged; b.txt is unstaged. Both are ticked.
        vm.status = WorkingCopyStatus(files: [
            Self.file("a.txt", staged: .modified, unstaged: .unmodified),
            Self.file("b.txt", staged: .unmodified, unstaged: .modified),
        ])
        vm.selectedFilePaths = ["a.txt", "b.txt"]
        // Running over a bogus working dir means stage() will throw, but
        // the precondition we care about is the filter. After the call,
        // b.txt should have been deselected (it was the target), a.txt
        // should still be ticked because stageSelected wouldn't have
        // touched it… BUT runStageOperation swallows the throw via
        // commitError so the deselect runs unconditionally. Asserting only
        // the filter semantics: a is still ticked, b was attempted and so
        // was dropped from selection.
        await vm.stageSelected()
        #expect(vm.selectedFilePaths.contains("a.txt"), "already-staged file shouldn't be cleared")
        #expect(vm.selectedFilePaths.contains("b.txt") == false, "target file should be cleared after batch")
    }

    @Test("unstageSelected ignores selected files that are not staged")
    func unstageSelectedOnlyConsidersStaged() async {
        let vm = Self.makeVM()
        vm.status = WorkingCopyStatus(files: [
            Self.file("a.txt", staged: .modified, unstaged: .unmodified),
            Self.file("b.txt", staged: .unmodified, unstaged: .modified),
        ])
        vm.selectedFilePaths = ["a.txt", "b.txt"]
        await vm.unstageSelected()
        #expect(vm.selectedFilePaths.contains("a.txt") == false, "target staged file should be cleared")
        #expect(vm.selectedFilePaths.contains("b.txt"), "unstaged file shouldn't be touched")
    }

    @Test("stageSelected with no matching files is a no-op")
    func stageSelectedEmptyIsNoOp() async {
        let vm = Self.makeVM()
        vm.status = WorkingCopyStatus(files: [
            Self.file("a.txt", staged: .modified, unstaged: .unmodified),
        ])
        // Only the staged file is selected — nothing to stage.
        vm.selectedFilePaths = ["a.txt"]
        await vm.stageSelected()
        // Selection unchanged because nothing was attempted.
        #expect(vm.selectedFilePaths == ["a.txt"])
    }
}
