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
        vm.commits = [a, b]
        #expect(vm.commitsById["aaa"] == a)
        #expect(vm.commitsById["bbb"] == b)
        #expect(vm.commitsById.count == 2)
    }

    @Test("commits append keeps commitsById in sync")
    func commitsByIdReflectsAppend() {
        let vm = Self.makeVM()
        vm.commits = [Self.commit("aaa")]
        vm.commits.append(Self.commit("bbb"))
        #expect(vm.commitsById.count == 2)
        #expect(vm.commitsById["bbb"]?.sha == "bbb")
    }

    @Test("commits removeAll keeps commitsById in sync")
    func commitsByIdReflectsRemoval() {
        let vm = Self.makeVM()
        vm.commits = [Self.commit("aaa"), Self.commit("bbb")]
        vm.commits.removeAll { $0.sha == "aaa" }
        #expect(vm.commitsById["aaa"] == nil)
        #expect(vm.commitsById["bbb"] != nil)
    }

    @Test("commitsById tolerates duplicate ids without trapping")
    func commitsByIdToleratesDuplicates() {
        // Regression for the trap shape `Dictionary(uniqueKeysWithValues:)`
        // would have produced if the `--skip` invariant ever leaked.
        let vm = Self.makeVM()
        let first = Self.commit("dup", subject: "first")
        let second = Self.commit("dup", subject: "second")
        vm.commits = [first, second]
        #expect(vm.commitsById["dup"] != nil)
    }

    @Test("Switching commit clears commit-file diff state")
    func switchingCommitClearsFileState() {
        let vm = Self.makeVM()
        vm.commits = [Self.commit("aaa")]
        vm.commitFileDiff = []
        vm.commitFileDiffEmptyState = .binary
        vm.loadingCommitFileDiff = true

        vm.selectedCommitId = "aaa"

        #expect(vm.selectedCommitFile == nil)
        #expect(vm.commitFileDiff.isEmpty)
        #expect(vm.commitFileDiffEmptyState == .empty)
        #expect(vm.loadingCommitFileDiff == false)
    }

    @Test("Switching commit bumps the diff generation token")
    func switchingCommitBumpsGen() {
        let vm = Self.makeVM()
        vm.commits = [Self.commit("aaa"), Self.commit("bbb")]
        vm.selectedCommitId = "aaa"
        let gen = vm.commitFileDiffGen
        vm.selectedCommitId = "bbb"
        #expect(vm.commitFileDiffGen > gen)
    }

    @Test("Reselecting the same commit is a no-op")
    func reselectingSameCommitIsNoOp() {
        let vm = Self.makeVM()
        vm.commits = [Self.commit("aaa")]
        vm.selectedCommitId = "aaa"
        let gen = vm.commitFileDiffGen
        vm.selectedCommitId = "aaa"
        #expect(vm.commitFileDiffGen == gen)
    }

    @Test("Setting selectedCommitFile to nil bumps the gen token")
    func clearingFileBumpsGen() {
        let vm = Self.makeVM()
        vm.selectedCommitFile = "Sources/foo.swift"
        let gen = vm.commitFileDiffGen
        vm.selectedCommitFile = nil
        #expect(vm.commitFileDiffGen > gen)
    }

    @Test("Setting the same selectedCommitFile twice doesn't bump the gen")
    func sameFileDoesNotBumpGen() {
        let vm = Self.makeVM()
        vm.selectedCommitFile = "Sources/foo.swift"
        let gen = vm.commitFileDiffGen
        vm.selectedCommitFile = "Sources/foo.swift"
        #expect(vm.commitFileDiffGen == gen)
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
        vm.selectedWorkingCopyFile = file
        vm.workingCopyDiff = []
        vm.workingCopyDiffEmptyState = .binary
        vm.loadingWorkingCopyDiff = true

        vm.selectedWorkingCopyFile = nil

        #expect(vm.workingCopyDiff.isEmpty)
        #expect(vm.workingCopyDiffEmptyState == .empty)
        #expect(vm.loadingWorkingCopyDiff == false)
    }

    @Test("Switching working-copy file bumps the working-copy diff gen")
    func switchingWorkingCopyFileBumpsGen() {
        let vm = Self.makeVM()
        let a = WorkingCopyFile(path: "a.swift", stagedStatus: .unmodified,
                                unstagedStatus: .modified, originalPath: nil)
        let b = WorkingCopyFile(path: "b.swift", stagedStatus: .unmodified,
                                unstagedStatus: .modified, originalPath: nil)
        vm.selectedWorkingCopyFile = a
        let gen = vm.workingCopyDiffGen
        vm.selectedWorkingCopyFile = b
        #expect(vm.workingCopyDiffGen > gen)
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
        vm.commitSubject = "WIP: keep me"
        vm.commitBody = "in-progress body"

        vm.amendMode = false  // already false

        #expect(vm.commitSubject == "WIP: keep me")
        #expect(vm.commitBody == "in-progress body")
    }

    @Test("Disabling amend after enabling clears typed text")
    func disablingAmendAfterEnableClearsText() {
        let vm = Self.makeVM()
        vm.amendMode = true
        // Simulate the user (or prefill) populating fields…
        vm.commitSubject = "fixup the thing"
        vm.commitBody = "details"

        vm.amendMode = false

        #expect(vm.commitSubject == "")
        #expect(vm.commitBody == "")
    }

    @Test("Enabling amend twice is a no-op for typed text")
    func enablingAmendTwiceKeepsText() {
        let vm = Self.makeVM()
        vm.amendMode = true
        vm.commitSubject = "edited"
        vm.amendMode = true  // idempotent
        #expect(vm.commitSubject == "edited")
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
        #expect(vm.selectedCommit == nil)
    }

    @Test("selectedCommit resolves through commitsById")
    func resolvesViaIndex() {
        let vm = Self.makeVM()
        let a = Commit(sha: "aaa", parentShas: [], authorName: "T",
                       authorEmail: "t@x", authorDate: .init(timeIntervalSince1970: 0),
                       subject: "s")
        vm.commits = [a]
        vm.selectedCommitId = "aaa"
        #expect(vm.selectedCommit == a)
    }

    @Test("selectedCommit returns nil when the id is no longer in commits")
    func nilWhenIdMissing() {
        let vm = Self.makeVM()
        let a = Commit(sha: "aaa", parentShas: [], authorName: "T",
                       authorEmail: "t@x", authorDate: .init(timeIntervalSince1970: 0),
                       subject: "s")
        vm.commits = [a]
        vm.selectedCommitId = "aaa"
        vm.commits = []  // e.g. resetLog cleared the page
        #expect(vm.selectedCommit == nil)
    }
}
