import Foundation
import Testing
@testable import gitForge

@Suite("StashDetailStore state", .serialized)
@MainActor
struct RepositoryViewModelStashDetailTests {

    private static func makeVM() -> RepositoryViewModel {
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        return RepositoryViewModel(repository: Repository(url: url))
    }

    private static func stash(_ index: Int) -> Stash {
        Stash(index: index, sha: "stash-\(index)", subject: "WIP \(index)")
    }

    @Test("select clears prior detail state and bumps the gen-token")
    func selectClearsAndBumps() {
        let vm = Self.makeVM()
        // Pre-seed values that select should reset.
        vm.stashDetail.error = "stale error"
        vm.stashDetail.selectedFile = "old/file.swift"
        let beforeGen = vm.stashDetail.detailGen

        vm.stashDetail.select(Self.stash(0))

        #expect(vm.stashDetail.selected?.index == 0)
        #expect(vm.stashDetail.detail == nil)
        #expect(vm.stashDetail.error == nil)
        #expect(vm.stashDetail.selectedFile == nil)
        #expect(vm.stashDetail.fileDiff.isEmpty)
        #expect(vm.stashDetail.detailGen == beforeGen &+ 1)
    }

    @Test("close clears state and bumps the gen-token")
    func closeClearsAndBumps() {
        let vm = Self.makeVM()
        vm.stashDetail.selected = Self.stash(2)
        vm.stashDetail.error = "old"
        vm.stashDetail.selectedFile = "x.swift"
        let beforeGen = vm.stashDetail.detailGen

        vm.stashDetail.close()

        #expect(vm.stashDetail.selected == nil)
        #expect(vm.stashDetail.detail == nil)
        #expect(vm.stashDetail.error == nil)
        #expect(vm.stashDetail.selectedFile == nil)
        #expect(vm.stashDetail.fileDiff.isEmpty)
        #expect(vm.stashDetail.detailGen == beforeGen &+ 1)
    }

    @Test("loadStashDetail short-circuits when no stash is selected but still bumps the token")
    func loadDetailNoSelection() async {
        let vm = Self.makeVM()
        let beforeGen = vm.stashDetail.detailGen
        await vm.stashDetail.load()
        #expect(vm.stashDetail.detailGen == beforeGen &+ 1)
        #expect(vm.stashDetail.detail == nil)
        #expect(vm.stashDetail.error == nil)
        #expect(vm.stashDetail.isLoading == false)
    }

    @Test("loadStashFileDiff is a no-op when no stash is selected")
    func loadFileDiffNoSelection() async {
        let vm = Self.makeVM()
        let beforeGen = vm.stashDetail.fileDiffGen
        await vm.stashDetail.loadFileDiff(at: "any.swift")
        // Guard runs *before* the bump, so neither token nor selection moves.
        #expect(vm.stashDetail.fileDiffGen == beforeGen)
        #expect(vm.stashDetail.selectedFile == nil)
        #expect(vm.stashDetail.fileDiff.isEmpty)
        #expect(vm.stashDetail.isLoadingFileDiff == false)
    }

    @Test("loadStashFileDiff bumps the gen-token and selects the path even when the diff fails")
    func loadFileDiffBumpsAndSelects() async {
        let vm = Self.makeVM()
        vm.stashDetail.selected = Self.stash(0)
        let beforeGen = vm.stashDetail.fileDiffGen
        await vm.stashDetail.loadFileDiff(at: "README.md")
        #expect(vm.stashDetail.fileDiffGen == beforeGen &+ 1)
        // selectedStashFile commits before the await so the row highlights
        // immediately; bogus dir's failure leaves diff empty.
        #expect(vm.stashDetail.selectedFile == "README.md")
        #expect(vm.stashDetail.fileDiff.isEmpty)
        #expect(vm.stashDetail.isLoadingFileDiff == false)
    }
}
