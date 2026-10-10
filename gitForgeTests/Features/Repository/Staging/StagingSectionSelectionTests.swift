import Foundation
import Testing
@testable import gitForge

@Suite("Changes — section selection and commit button")
@MainActor
struct StagingSectionSelectionTests {

    private static func file(_ path: String) -> WorkingCopyFile {
        WorkingCopyFile(path: path, stagedStatus: .unmodified, unstagedStatus: .modified, originalPath: nil)
    }

    @Test("Select-all state follows the ticked paths of the section only")
    func state() {
        let paths = ["a", "b", "c"]
        #expect(StagingSectionSelection(paths: paths, selected: []) == .none)
        #expect(StagingSectionSelection(paths: paths, selected: ["b", "elsewhere"]) == .some(1))
        #expect(StagingSectionSelection(paths: paths, selected: ["a", "b", "c", "elsewhere"]) == .all)
        #expect(StagingSectionSelection(paths: [], selected: ["a"]) == .none)
    }

    @Test("Ticked count resolves .all to the section size")
    func count() {
        #expect(StagingSectionSelection.none.count(of: 4) == 0)
        #expect(StagingSectionSelection.some(2).count(of: 4) == 2)
        #expect(StagingSectionSelection.all.count(of: 4) == 4)
    }

    @Test("setSelection ticks a whole section and unticks only that section")
    func setSelection() {
        let vm = RepositoryViewModel(repository: Repository(url: URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")))
        vm.selectedFilePaths = ["other"]
        let section = [Self.file("a"), Self.file("b")]
        vm.setSelection(section, selected: true)
        #expect(vm.selectedFilePaths == ["a", "b", "other"])
        vm.setSelection(section, selected: false)
        #expect(vm.selectedFilePaths == ["other"])
    }

    @Test("Commit button names the file count and branch, or the amend")
    func commitTitle() {
        #expect(CommitButtonTitle.make(fileCount: 1, branch: "main", amend: false) == "Commit 1 file to main")
        #expect(CommitButtonTitle.make(fileCount: 3, branch: "main", amend: false) == "Commit 3 files to main")
        #expect(CommitButtonTitle.make(fileCount: 2, branch: nil, amend: false) == "Commit to detached HEAD")
        #expect(CommitButtonTitle.make(fileCount: 0, branch: "main", amend: true) == "Amend last commit")
    }
}
