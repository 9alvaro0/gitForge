import Foundation
import Testing
@testable import gitForge

@Suite("RepositoryViewModel — amend guard")
@MainActor
struct RepositoryViewModelAmendGuardTests {

    private static func makeVM() -> RepositoryViewModel {
        // Bogus working dir — these tests only exercise pre-flight guards in
        // commit() / amendWouldRewritePublishedHistory, which return before
        // hitting the cli.
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        return RepositoryViewModel(repository: Repository(url: url))
    }

    @Test("amendWouldRewritePublishedHistory is false when amendMode is off")
    func falseWhenNotAmending() {
        let vm = Self.makeVM()
        vm.upstream = "origin/main"
        vm.aheadCount = 0
        #expect(vm.amendWouldRewritePublishedHistory == false)
    }

    @Test("amendWouldRewritePublishedHistory is false without upstream")
    func falseWithoutUpstream() {
        let vm = Self.makeVM()
        vm.amendMode = true
        vm.upstream = nil
        vm.aheadCount = 0
        #expect(vm.amendWouldRewritePublishedHistory == false)
    }

    @Test("amendWouldRewritePublishedHistory is false when ahead of upstream")
    func falseWhenAhead() {
        let vm = Self.makeVM()
        vm.amendMode = true
        vm.upstream = "origin/main"
        vm.aheadCount = 1
        #expect(vm.amendWouldRewritePublishedHistory == false)
    }

    @Test("amendWouldRewritePublishedHistory is true when amending HEAD that's on the remote")
    func trueWhenAmendingPublishedHead() {
        let vm = Self.makeVM()
        vm.amendMode = true
        vm.upstream = "origin/main"
        vm.aheadCount = 0
        #expect(vm.amendWouldRewritePublishedHistory == true)
    }

    @Test("commit() refuses to amend a published commit without confirmation")
    func commitBlocksUnconfirmedAmend() async {
        let vm = Self.makeVM()
        vm.amendMode = true
        vm.upstream = "origin/main"
        vm.aheadCount = 0
        vm.commitSubject = "rewrite"
        let ok = await vm.commit()
        #expect(ok == false)
        #expect(vm.commitError?.contains("already on the remote") == true)
    }

    @Test("commit() guard fires after subject/staged checks, not before")
    func commitGuardOrderEmptySubjectFirst() async {
        let vm = Self.makeVM()
        vm.amendMode = true
        vm.upstream = "origin/main"
        vm.aheadCount = 0
        vm.commitSubject = "   " // empty after trim
        let ok = await vm.commit()
        #expect(ok == false)
        // Should be the subject error, not the amend-guard error.
        #expect(vm.commitError == "Commit subject cannot be empty")
    }

    @Test("commit() with confirmedAmendOfPublished: true bypasses the guard (still fails on bogus cli)")
    func commitWithConfirmationBypassesGuard() async {
        let vm = Self.makeVM()
        vm.amendMode = true
        vm.upstream = "origin/main"
        vm.aheadCount = 0
        vm.commitSubject = "rewrite"
        let ok = await vm.commit(confirmedAmendOfPublished: true)
        // The guard didn't fire; failure (if any) comes from the cli call on
        // a bogus working dir — and the error message must NOT be the guard's.
        #expect(ok == false)
        #expect(vm.commitError?.contains("already on the remote") == false)
    }
}
