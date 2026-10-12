import Foundation
import Testing
@testable import gitForge

@Suite("RepositoryViewModel — selection state", .serialized)
@MainActor
struct RepositoryViewModelSelectionTests {

    private static func makeVM() -> RepositoryViewModel {
        // Pointing the VM at a non-existent path is fine for these tests:
        // the suite only exercises property-observer side effects, which
        // never reach into `cli`.
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        return RepositoryViewModel(repository: Repository(url: url))
    }

    private static func commit(_ sha: String, subject: String = "subject") -> Commit {
        Commit(
            sha: sha,
            parentShas: [],
            authorName: "Test",
            authorEmail: "t@example.com",
            authorDate: .init(timeIntervalSince1970: 0),
            subject: subject
        )
    }

    @Test("commits assignment populates commitsById")
    func commitsByIdPopulatesOnAssignment() {
        let vm = Self.makeVM()
        let a = Self.commit("aaa")
        let b = Self.commit("bbb")
        vm.history.commits = [a, b]
        #expect(vm.history.commitsById["aaa"] == a)
        #expect(vm.history.commitsById["bbb"] == b)
        #expect(vm.history.commitsById.count == 2)
    }

    @Test("commits append keeps commitsById in sync")
    func commitsByIdReflectsAppend() {
        let vm = Self.makeVM()
        vm.history.commits = [Self.commit("aaa")]
        vm.history.commits.append(Self.commit("bbb"))
        #expect(vm.history.commitsById.count == 2)
        #expect(vm.history.commitsById["bbb"]?.sha == "bbb")
    }

    @Test("commits removeAll keeps commitsById in sync")
    func commitsByIdReflectsRemoval() {
        let vm = Self.makeVM()
        vm.history.commits = [Self.commit("aaa"), Self.commit("bbb")]
        vm.history.commits.removeAll { $0.sha == "aaa" }
        #expect(vm.history.commitsById["aaa"] == nil)
        #expect(vm.history.commitsById["bbb"] != nil)
    }

    @Test("commitsById tolerates duplicate ids without trapping")
    func commitsByIdToleratesDuplicates() {
        // Regression for the trap shape `Dictionary(uniqueKeysWithValues:)`
        // would have produced if the `--skip` invariant ever leaked.
        let vm = Self.makeVM()
        let first = Self.commit("dup", subject: "first")
        let second = Self.commit("dup", subject: "second")
        vm.history.commits = [first, second]
        #expect(vm.history.commitsById["dup"] != nil)
    }

    @Test("Switching commit clears commit-file diff state")
    func switchingCommitClearsFileState() {
        let vm = Self.makeVM()
        vm.history.commits = [Self.commit("aaa")]
        vm.history.commitFileDiff = []
        vm.history.commitFileDiffEmptyState = .binary
        vm.history.loadingCommitFileDiff = true

        vm.history.selectedCommitId = "aaa"

        #expect(vm.history.selectedCommitFile == nil)
        #expect(vm.history.commitFileDiff.isEmpty)
        #expect(vm.history.commitFileDiffEmptyState == .empty)
        #expect(vm.history.loadingCommitFileDiff == false)
    }

    @Test("Switching commit bumps the diff generation token")
    func switchingCommitBumpsGen() {
        let vm = Self.makeVM()
        vm.history.commits = [Self.commit("aaa"), Self.commit("bbb")]
        vm.history.selectedCommitId = "aaa"
        let gen = vm.history.commitFileDiffGen
        vm.history.selectedCommitId = "bbb"
        #expect(vm.history.commitFileDiffGen > gen)
    }

    @Test("Reselecting the same commit is a no-op")
    func reselectingSameCommitIsNoOp() {
        let vm = Self.makeVM()
        vm.history.commits = [Self.commit("aaa")]
        vm.history.selectedCommitId = "aaa"
        let gen = vm.history.commitFileDiffGen
        vm.history.selectedCommitId = "aaa"
        #expect(vm.history.commitFileDiffGen == gen)
    }

    @Test("Setting selectedCommitFile to nil bumps the gen token")
    func clearingFileBumpsGen() {
        let vm = Self.makeVM()
        vm.history.selectedCommitFile = "Sources/foo.swift"
        let gen = vm.history.commitFileDiffGen
        vm.history.selectedCommitFile = nil
        #expect(vm.history.commitFileDiffGen > gen)
    }

    @Test("Setting the same selectedCommitFile twice doesn't bump the gen")
    func sameFileDoesNotBumpGen() {
        let vm = Self.makeVM()
        vm.history.selectedCommitFile = "Sources/foo.swift"
        let gen = vm.history.commitFileDiffGen
        vm.history.selectedCommitFile = "Sources/foo.swift"
        #expect(vm.history.commitFileDiffGen == gen)
    }

    @Test("Clearing the working-copy file resets diff state")
    func clearingWorkingCopyFileResetsState() {
        let vm = Self.makeVM()
        let file = WorkingCopyFile(
            path: "Sources/foo.swift",
            stagedStatus: .unmodified,
            unstagedStatus: .modified,
            originalPath: nil
        )
        vm.workingCopy.selectedWorkingCopyFile = file
        vm.workingCopy.workingCopyDiff = []
        vm.workingCopy.workingCopyDiffEmptyState = .binary
        vm.workingCopy.loadingWorkingCopyDiff = true

        vm.workingCopy.selectedWorkingCopyFile = nil

        #expect(vm.workingCopy.workingCopyDiff.isEmpty)
        #expect(vm.workingCopy.workingCopyDiffEmptyState == .empty)
        #expect(vm.workingCopy.loadingWorkingCopyDiff == false)
    }

    @Test("Switching working-copy file bumps the working-copy diff gen")
    func switchingWorkingCopyFileBumpsGen() {
        let vm = Self.makeVM()
        let a = WorkingCopyFile(path: "a.swift", stagedStatus: .unmodified,
                                unstagedStatus: .modified, originalPath: nil)
        let b = WorkingCopyFile(path: "b.swift", stagedStatus: .unmodified,
                                unstagedStatus: .modified, originalPath: nil)
        vm.workingCopy.selectedWorkingCopyFile = a
        let gen = vm.workingCopy.workingCopyDiffGen
        vm.workingCopy.selectedWorkingCopyFile = b
        #expect(vm.workingCopy.workingCopyDiffGen > gen)
    }
}

@Suite("RepositoryViewModel — amend mode", .serialized)
@MainActor
struct RepositoryViewModelAmendTests {

    private static func makeVM() -> RepositoryViewModel {
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        return RepositoryViewModel(repository: Repository(url: url))
    }

    @Test("Disabling amend while already disabled keeps typed text")
    func disablingAmendWhileDisabledKeepsText() {
        // Regression: the previous didSet shape wiped subject/body on any
        // false→false assignment.
        let vm = Self.makeVM()
        vm.workingCopy.commitSubject = "WIP: keep me"
        vm.workingCopy.commitBody = "in-progress body"

        vm.workingCopy.amendMode = false  // already false

        #expect(vm.workingCopy.commitSubject == "WIP: keep me")
        #expect(vm.workingCopy.commitBody == "in-progress body")
    }

    @Test("Disabling amend after enabling clears typed text")
    func disablingAmendAfterEnableClearsText() {
        let vm = Self.makeVM()
        vm.workingCopy.amendMode = true
        // Simulate the user (or prefill) populating fields…
        vm.workingCopy.commitSubject = "fixup the thing"
        vm.workingCopy.commitBody = "details"

        vm.workingCopy.amendMode = false

        #expect(vm.workingCopy.commitSubject == "")
        #expect(vm.workingCopy.commitBody == "")
    }

    @Test("Enabling amend twice is a no-op for typed text")
    func enablingAmendTwiceKeepsText() {
        let vm = Self.makeVM()
        vm.workingCopy.amendMode = true
        vm.workingCopy.commitSubject = "edited"
        vm.workingCopy.amendMode = true  // idempotent
        #expect(vm.workingCopy.commitSubject == "edited")
    }
}

@Suite("RepositoryViewModel — refs derivation", .serialized)
@MainActor
struct RepositoryViewModelRefsTests {

    private static func makeVM() -> RepositoryViewModel {
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        return RepositoryViewModel(repository: Repository(url: url))
    }

    @Test("refsBySha groups refs by target sha")
    func refsByShaGroups() {
        let vm = Self.makeVM()
        let a1 = GitRef(name: "main", kind: .localBranch, targetSha: "aaa", isHead: true)
        let a2 = GitRef(name: "feature", kind: .localBranch, targetSha: "aaa", isHead: false)
        let b1 = GitRef(name: "v1", kind: .tag, targetSha: "bbb", isHead: false)
        vm.refs = [a1, a2, b1]
        #expect(vm.refsBySha["aaa"]?.count == 2)
        #expect(vm.refsBySha["bbb"]?.count == 1)
    }

    @Test("Computed branch/tag views filter and sort by name")
    func filteredViewsAreSorted() {
        let vm = Self.makeVM()
        vm.refs = [
            GitRef(name: "main", kind: .localBranch, targetSha: "1", isHead: true),
            GitRef(name: "alpha", kind: .localBranch, targetSha: "2", isHead: false),
            GitRef(name: "origin/main", kind: .remoteBranch(remote: "origin"),
                   targetSha: "1", isHead: false),
            GitRef(name: "v1", kind: .tag, targetSha: "9", isHead: false),
        ]
        #expect(vm.localBranches.map(\.name) == ["alpha", "main"])
        #expect(vm.remoteBranches.map(\.name) == ["origin/main"])
        #expect(vm.tags.map(\.name) == ["v1"])
    }
}

@Suite("RepositoryViewModel — selectedCommit", .serialized)
@MainActor
struct RepositoryViewModelSelectedCommitTests {

    private static func makeVM() -> RepositoryViewModel {
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        return RepositoryViewModel(repository: Repository(url: url))
    }

    @Test("selectedCommit returns nil when nothing is selected")
    func nilWhenUnselected() {
        let vm = Self.makeVM()
        #expect(vm.history.selectedCommit == nil)
    }

    @Test("selectedCommit resolves through commitsById")
    func resolvesViaIndex() {
        let vm = Self.makeVM()
        let a = Commit(sha: "aaa", parentShas: [], authorName: "T",
                       authorEmail: "t@x", authorDate: .init(timeIntervalSince1970: 0),
                       subject: "s")
        vm.history.commits = [a]
        vm.history.selectedCommitId = "aaa"
        #expect(vm.history.selectedCommit == a)
    }

    @Test("selectedCommit returns nil when the id is no longer in commits")
    func nilWhenIdMissing() {
        let vm = Self.makeVM()
        let a = Commit(sha: "aaa", parentShas: [], authorName: "T",
                       authorEmail: "t@x", authorDate: .init(timeIntervalSince1970: 0),
                       subject: "s")
        vm.history.commits = [a]
        vm.history.selectedCommitId = "aaa"
        vm.history.commits = []  // e.g. a fresh scope before the first page
        #expect(vm.history.selectedCommit == nil)
    }
}
