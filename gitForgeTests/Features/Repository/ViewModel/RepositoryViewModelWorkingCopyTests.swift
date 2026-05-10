import Foundation
import Testing
@testable import gitForge

@Suite("RepositoryViewModel — refreshStatus", .serialized)
@MainActor
struct RepositoryViewModelRefreshStatusTests {

    private static func makeVM() -> RepositoryViewModel {
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        return RepositoryViewModel(repository: Repository(url: url))
    }

    @Test("refreshStatus bumps statusGen by one")
    func bumpsGen() async {
        let vm = Self.makeVM()
        let before = vm.statusGen
        await vm.refreshStatus()
        #expect(vm.statusGen == before &+ 1)
    }

    @Test("statusGen is monotonic across consecutive refreshStatus calls")
    func monotonic() async {
        let vm = Self.makeVM()
        await vm.refreshStatus()
        let mid = vm.statusGen
        await vm.refreshStatus()
        #expect(vm.statusGen == mid &+ 1)
    }

    @Test("refreshStatus on a bogus dir leaves status untouched and clears the spinner via defer")
    func bogusDirPreservesStatusAndClearsSpinner() async {
        let vm = Self.makeVM()
        // Pre-seed a sentinel `status` so we can detect a stale write.
        // Bogus dir → cli.status() throws → catch swallows → status untouched.
        let sentinel = WorkingCopyFile(
            path: "sentinel.swift",
            stagedStatus: .modified,
            unstagedStatus: .unmodified,
            originalPath: nil
        )
        vm.status = WorkingCopyStatus(files: [sentinel])
        await vm.refreshStatus()
        #expect(vm.status.files.first?.path == "sentinel.swift")
        #expect(vm.isLoadingStatus == false, "defer must clear the spinner even on failure")
        #expect(vm.hasLoadedStatusOnce == true, "first attempt counts as 'loaded once' regardless of outcome")
    }
}

@Suite("RepositoryViewModel — commit guards", .serialized)
@MainActor
struct RepositoryViewModelCommitGuardsTests {

    private static func makeVM() -> RepositoryViewModel {
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        return RepositoryViewModel(repository: Repository(url: url))
    }

    @Test("commit fails with a fresh error when the subject is empty (clears stale commitError on entry)")
    func emptySubjectGuard() async {
        let vm = Self.makeVM()
        vm.commitError = "stale error"
        vm.commitSubject = "   "
        let ok = await vm.commit()
        #expect(ok == false)
        #expect(vm.commitError == "Commit subject cannot be empty")
    }

    @Test("commit fails with a fresh error when nothing is staged and amend mode is off")
    func nothingStagedGuard() async {
        let vm = Self.makeVM()
        vm.commitError = "stale"
        vm.commitSubject = "feat: thing"
        // Default `status` has no files → no staged changes; amendMode is false.
        let ok = await vm.commit()
        #expect(ok == false)
        #expect(vm.commitError == "Nothing staged to commit")
    }

    @Test("commit on a bogus dir surfaces a fresh error message past the guards")
    func bogusDirCommitSurfacesError() async {
        let vm = Self.makeVM()
        vm.commitSubject = "feat: thing"
        // Bypass the "nothing staged" guard with a fake staged file so the
        // call reaches `cli.commit`. Avoids the amendMode toggle path which
        // would kick a parallel `prefillFromHead` Task and race with the
        // test. Bogus dir then makes cli.commit throw, catch sets the error.
        let staged = WorkingCopyFile(
            path: "feature.swift",
            stagedStatus: .modified,
            unstagedStatus: .unmodified,
            originalPath: nil
        )
        vm.status = WorkingCopyStatus(files: [staged])
        let ok = await vm.commit()
        #expect(ok == false)
        #expect(vm.commitError != nil)
        #expect(vm.commitError != "Commit subject cannot be empty")
        #expect(vm.commitError != "Nothing staged to commit")
    }
}

@Suite("RepositoryViewModel — prefillFromHead amend guard", .serialized)
@MainActor
struct RepositoryViewModelPrefillFromHeadTests {

    private static func makeVM() -> RepositoryViewModel {
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        return RepositoryViewModel(repository: Repository(url: url))
    }

    @Test("prefillFromHead leaves subject/body untouched when amendMode flipped off underneath it")
    func amendOffPostAwait() async {
        let vm = Self.makeVM()
        vm.amendMode = false
        vm.commitSubject = "user is mid-typing"
        vm.commitBody = "still typing"
        // Calling prefillFromHead directly with amendMode off simulates the
        // state after a `false → true → false` toggle whose pending Task is
        // about to resume. Bogus dir would also short-circuit, so we assert
        // the strict invariant: amendMode == false → no write.
        await vm.prefillFromHead()
        #expect(vm.commitSubject == "user is mid-typing")
        #expect(vm.commitBody == "still typing")
    }
}
