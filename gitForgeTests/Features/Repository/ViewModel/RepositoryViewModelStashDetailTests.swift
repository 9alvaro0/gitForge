import Foundation
import Testing
@testable import gitForge

@Suite("RepositoryViewModel — stash detail state", .serialized)
@MainActor
struct RepositoryViewModelStashDetailTests {

    private static func makeVM() -> RepositoryViewModel {
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        return RepositoryViewModel(repository: Repository(url: url))
    }

    private static func stash(_ index: Int) -> Stash {
        Stash(index: index, sha: "stash-\(index)", subject: "WIP \(index)")
    }

    @Test("selectStash clears prior detail state and bumps the gen-token")
    func selectClearsAndBumps() {
        let vm = Self.makeVM()
        // Pre-seed values that selectStash should reset.
        vm.stashDetailError = "stale error"
        vm.selectedStashFile = "old/file.swift"
        let beforeGen = vm.stashDetailGen

        vm.selectStash(Self.stash(0))

        #expect(vm.selectedStash?.index == 0)
        #expect(vm.stashDetail == nil)
        #expect(vm.stashDetailError == nil)
        #expect(vm.selectedStashFile == nil)
        #expect(vm.stashFileDiff.isEmpty)
        #expect(vm.stashDetailGen == beforeGen &+ 1)
    }

    @Test("closeStashDetail clears state and bumps the gen-token")
    func closeClearsAndBumps() {
        let vm = Self.makeVM()
        vm.selectedStash = Self.stash(2)
        vm.stashDetailError = "old"
        vm.selectedStashFile = "x.swift"
        let beforeGen = vm.stashDetailGen

        vm.closeStashDetail()

        #expect(vm.selectedStash == nil)
        #expect(vm.stashDetail == nil)
        #expect(vm.stashDetailError == nil)
        #expect(vm.selectedStashFile == nil)
        #expect(vm.stashFileDiff.isEmpty)
        #expect(vm.stashDetailGen == beforeGen &+ 1)
    }

    @Test("loadStashDetail short-circuits when no stash is selected but still bumps the token")
    func loadDetailNoSelection() async {
        let vm = Self.makeVM()
        let beforeGen = vm.stashDetailGen
        await vm.loadStashDetail()
        #expect(vm.stashDetailGen == beforeGen &+ 1)
        #expect(vm.stashDetail == nil)
        #expect(vm.stashDetailError == nil)
        #expect(vm.stashDetailLoading == false)
    }

    @Test("loadStashFileDiff is a no-op when no stash is selected")
    func loadFileDiffNoSelection() async {
        let vm = Self.makeVM()
        let beforeGen = vm.stashFileDiffGen
        await vm.loadStashFileDiff(at: "any.swift")
        // Guard runs *before* the bump, so neither token nor selection moves.
        #expect(vm.stashFileDiffGen == beforeGen)
        #expect(vm.selectedStashFile == nil)
        #expect(vm.stashFileDiff.isEmpty)
        #expect(vm.loadingStashFileDiff == false)
    }

    @Test("loadStashFileDiff bumps the gen-token and selects the path even when the diff fails")
    func loadFileDiffBumpsAndSelects() async {
        let vm = Self.makeVM()
        vm.selectedStash = Self.stash(0)
        let beforeGen = vm.stashFileDiffGen
        await vm.loadStashFileDiff(at: "README.md")
        #expect(vm.stashFileDiffGen == beforeGen &+ 1)
        // selectedStashFile commits before the await so the row highlights
        // immediately; bogus dir's failure leaves diff empty.
        #expect(vm.selectedStashFile == "README.md")
        #expect(vm.stashFileDiff.isEmpty)
        #expect(vm.loadingStashFileDiff == false)
    }
}
