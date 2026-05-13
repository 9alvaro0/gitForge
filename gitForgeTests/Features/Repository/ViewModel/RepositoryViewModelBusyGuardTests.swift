import Foundation
import Testing
@testable import gitForge

@Suite("RepositoryViewModel — busy guards", .serialized)
@MainActor
struct RepositoryViewModelBusyGuardTests {

    private static func makeVM() -> RepositoryViewModel {
        // Bogus working dir: the guards return before any cli call, so a
        // non-existent path is fine for asserting that the bail-out fires.
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        return RepositoryViewModel(repository: Repository(url: url))
    }

    private static func makeCommit(sha: String = "abc1234deadbeef") -> Commit {
        Commit(sha: sha, parentShas: [], authorName: "X", authorEmail: "x@x", authorDate: Date(), subject: "test")
    }

    @Test("commit() bails immediately when isMutating is set")
    func commitBailsWhenBusy() async {
        let vm = Self.makeVM()
        vm.isMutating = true
        vm.commitSubject = "subject"
        let ok = await vm.commit()
        #expect(ok == false)
        // The guard returns before touching commitError — distinguish from
        // the "subject empty"/"nothing staged" paths that DO set it.
        #expect(vm.commitError == nil)
    }

    @Test("stashAll returns .failure with GitError.busy when isMutating is set")
    func stashAllBailsWhenBusy() async {
        let vm = Self.makeVM()
        // Pretend there's something to stash, otherwise the .nothingToStash
        // guard fires first.
        vm.status = WorkingCopyStatus(files: [
            WorkingCopyFile(path: "f.txt", stagedStatus: .modified, unstagedStatus: .unmodified, originalPath: nil)
        ])
        vm.isMutating = true
        let result = await vm.stashAll()
        guard case .failure(let error) = result else {
            Issue.record("Expected .failure, got \(result)")
            return
        }
        #expect((error as? GitError) == .busy)
    }

    @Test("applyStash returns .failed when isMutating is set")
    func applyStashBailsWhenBusy() async {
        let vm = Self.makeVM()
        vm.isMutating = true
        let stash = Stash(index: 0, sha: "deadbeef", subject: "WIP")
        let outcome = await vm.applyStash(stash, drop: false)
        guard case .failed(let message) = outcome else {
            Issue.record("Expected .failed, got \(outcome)")
            return
        }
        #expect(message.contains("Another operation"))
    }

    @Test("dropStash returns .failure with GitError.busy when isMutating is set")
    func dropStashBailsWhenBusy() async {
        let vm = Self.makeVM()
        vm.isMutating = true
        let stash = Stash(index: 0, sha: "deadbeef", subject: "WIP")
        let result = await vm.dropStash(stash)
        guard case .failure(let error) = result else {
            Issue.record("Expected .failure, got \(result)")
            return
        }
        #expect((error as? GitError) == .busy)
    }

    @Test("abortStashApply returns .failure with GitError.busy when isMutating is set")
    func abortStashApplyBailsWhenBusy() async {
        let vm = Self.makeVM()
        vm.isMutating = true
        let result = await vm.abortStashApply()
        guard case .failure(let error) = result else {
            Issue.record("Expected .failure, got \(result)")
            return
        }
        #expect((error as? GitError) == .busy)
    }

    @Test("reset returns .failed when isMutating is set")
    func resetBailsWhenBusy() async {
        let vm = Self.makeVM()
        vm.isMutating = true
        let outcome = await vm.reset(to: "abc", mode: .soft)
        guard case .failed(let message) = outcome else {
            Issue.record("Expected .failed, got \(outcome)")
            return
        }
        #expect(message.contains("Another operation"))
    }

    @Test("cherryPick returns .failed when isMutating is set")
    func cherryPickBailsWhenBusy() async {
        let vm = Self.makeVM()
        vm.isMutating = true
        let outcome = await vm.cherryPick(Self.makeCommit())
        guard case .failed(let message) = outcome else {
            Issue.record("Expected .failed, got \(outcome)")
            return
        }
        #expect(message.contains("Another operation"))
    }

    @Test("revert returns .failed when isMutating is set")
    func revertBailsWhenBusy() async {
        let vm = Self.makeVM()
        vm.isMutating = true
        let outcome = await vm.revert(Self.makeCommit())
        guard case .failed(let message) = outcome else {
            Issue.record("Expected .failed, got \(outcome)")
            return
        }
        #expect(message.contains("Another operation"))
    }

    @Test("runStageOperation skips the block when isMutating is set")
    func runStageOperationBailsWhenBusy() async {
        let vm = Self.makeVM()
        vm.isMutating = true
        var blockCalled = false
        await vm.runStageOperation { blockCalled = true }
        // The whole point: the closure must not run if another mutation is
        // already in flight. A doubled discardChanges would otherwise hit
        // git twice and race the index lock.
        #expect(blockCalled == false)
        #expect(vm.commitError == nil)
    }
}
