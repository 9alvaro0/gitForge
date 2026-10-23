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
        let before = vm.workingCopy.statusGen
        await vm.workingCopy.refreshStatus()
        #expect(vm.workingCopy.statusGen == before &+ 1)
    }

    @Test("statusGen is monotonic across consecutive refreshStatus calls")
    func monotonic() async {
        let vm = Self.makeVM()
        await vm.workingCopy.refreshStatus()
        let mid = vm.workingCopy.statusGen
        await vm.workingCopy.refreshStatus()
        #expect(vm.workingCopy.statusGen == mid &+ 1)
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
        vm.workingCopy.status = WorkingCopyStatus(files: [sentinel])
        await vm.workingCopy.refreshStatus()
        #expect(vm.workingCopy.status.files.first?.path == "sentinel.swift")
        #expect(vm.workingCopy.isLoadingStatus == false, "defer must clear the spinner even on failure")
        #expect(vm.workingCopy.hasLoadedStatusOnce == true, "first attempt counts as 'loaded once' regardless of outcome")
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
        vm.workingCopy.commitSubject = "   "
        let ok = await vm.commit()
        #expect(ok == false)
        #expect(vm.commitError == "Commit subject cannot be empty")
    }

    @Test("commit fails with a fresh error when nothing is staged and amend mode is off")
    func nothingStagedGuard() async {
        let vm = Self.makeVM()
        vm.commitError = "stale"
        vm.workingCopy.commitSubject = "feat: thing"
        // Default `status` has no files → no staged changes; amendMode is false.
        let ok = await vm.commit()
        #expect(ok == false)
        #expect(vm.commitError == "Nothing staged to commit")
    }

    @Test("commit on a bogus dir surfaces a fresh error message past the guards")
    func bogusDirCommitSurfacesError() async {
        let vm = Self.makeVM()
        vm.workingCopy.commitSubject = "feat: thing"
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
        vm.workingCopy.status = WorkingCopyStatus(files: [staged])
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
        vm.workingCopy.amendMode = false
        vm.workingCopy.commitSubject = "user is mid-typing"
        vm.workingCopy.commitBody = "still typing"
        // Calling prefillFromHead directly with amendMode off simulates the
        // state after a `false → true → false` toggle whose pending Task is
        // about to resume. Bogus dir would also short-circuit, so we assert
        // the strict invariant: amendMode == false → no write.
        await vm.workingCopy.prefillFromHead()
        #expect(vm.workingCopy.commitSubject == "user is mid-typing")
        #expect(vm.workingCopy.commitBody == "still typing")
    }
}

@Suite("WorkingCopyStore — line counts", .serialized)
@MainActor
struct WorkingCopyLineCountsTests {

    @Test("refreshStatus fills the staged and unstaged counts")
    func refreshFillsCounts() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("init", files: ["a.txt": "a\n", "b.txt": "b\n"])
            try repo.write("a\nmore\n", to: "a.txt")
            try repo.git("add", "a.txt")
            try repo.write("", to: "b.txt")
        }
        defer { repo.remove() }
        let vm = RepositoryViewModel(repository: Repository(url: repo.url))
        await vm.workingCopy.refreshStatus()
        #expect(vm.workingCopy.stagedLineCounts == ["a.txt": DiffStats(additions: 1, deletions: 0)])
        #expect(vm.workingCopy.unstagedLineCounts == ["b.txt": DiffStats(additions: 0, deletions: 1)])
    }
}

@Suite("RepositoryViewModel — uncommitted changes in the graph", .serialized)
@MainActor
struct RepositoryViewModelUncommittedGraphTests {

    @Test("Editing a file and refreshing the status puts the connector in the graph")
    func editShowsConnector() async throws {
        let repo = try await GitTestRepo.make { try $0.commit("c0", files: ["f.txt": "0\n"]) }
        defer { repo.remove() }
        let vm = RepositoryViewModel(repository: Repository(url: repo.url))
        await vm.loadRefs()
        await vm.history.loadInitial()
        #expect(!vm.history.showsUncommittedRow)
        try repo.write("1\n", to: "f.txt")
        await vm.workingCopy.refreshStatus()
        await waitUntil { vm.history.showsUncommittedRow }
        #expect(vm.history.showsUncommittedRow)
        let first = try #require(vm.history.graphLayouts.first)
        #expect(first.stepsAbove == [.uncommitted])
    }
}
