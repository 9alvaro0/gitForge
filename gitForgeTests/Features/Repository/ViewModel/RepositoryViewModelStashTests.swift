import Foundation
import Testing
@testable import gitForge

@Suite("RepositoryViewModel — stash guards", .serialized)
@MainActor
struct RepositoryViewModelStashTests {

    private static func makeVM() -> RepositoryViewModel {
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        return RepositoryViewModel(repository: Repository(url: url))
    }

    @Test("stashAll fails with .nothingToStash when the working tree is clean")
    func stashAllNothingToStash() async {
        let vm = Self.makeVM()
        // Default `status` has no files → `isClean == true`. The guard fires
        // before touching the cli, so a bogus working dir is fine here.
        let result = await vm.stashAll()
        guard case .failure(let error) = result else {
            Issue.record("Expected .failure for a clean working tree")
            return
        }
        guard let stashError = error as? StashError, case .nothingToStash = stashError else {
            Issue.record("Expected StashError.nothingToStash, got \(error)")
            return
        }
    }

    @Test("StashError.nothingToStash carries a non-empty user-facing description")
    func stashErrorDescription() {
        let message = StashError.nothingToStash.errorDescription
        #expect(message?.isEmpty == false)
    }

    @Test("dropStash returns .failure on a bogus working dir without crashing")
    func dropStashSurfacesFailure() async {
        let vm = Self.makeVM()
        let stash = Stash(index: 0, sha: "deadbeef", subject: "WIP")
        let result = await vm.dropStash(stash)
        guard case .failure = result else {
            Issue.record("Expected .failure for a bogus working dir")
            return
        }
    }

    @Test("applyStash returns .failed on a bogus working dir without crashing")
    func applyStashSurfacesFailure() async {
        let vm = Self.makeVM()
        let stash = Stash(index: 0, sha: "deadbeef", subject: "WIP")
        let outcome = await vm.applyStash(stash, drop: false)
        // Bogus dir → cli.stashApply throws GitError.invalidWorkingDirectory,
        // catch fires, refreshAfterIntegration also no-ops on bogus dir, so
        // mergeState stays `.clean` and we end on `.failed`.
        guard case .failed = outcome else {
            Issue.record("Expected .failed, got \(outcome)")
            return
        }
    }

    @Test("A conflicted apply remembers the stash and abort keeps unrelated work")
    func conflictedApplyThenAbort() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("init", files: ["conf.txt": "base\n", "mine.txt": "m\n"])
            try repo.write("from-stash\n", to: "conf.txt")
            try repo.git("stash", "push", "-q")
            try repo.commit("conflicting", files: ["conf.txt": "from-head\n"])
            try repo.write("my work\n", to: "mine.txt")
        }
        defer { repo.remove() }

        let vm = RepositoryViewModel(repository: Repository(url: repo.url))
        let stash = try #require(try await repo.cli.stashes().first)

        #expect(await vm.applyStash(stash, drop: false) == .conflicts)
        #expect(vm.conflictedStashSha == stash.sha)

        guard case .success = await vm.abortStashApply() else {
            Issue.record("abortStashApply failed")
            return
        }
        #expect(vm.conflictedStashSha == nil)
        #expect(vm.mergeState == .clean)
        #expect(repo.read("mine.txt") == "my work\n")
        #expect(repo.read("conf.txt") == "from-head\n")
    }
}

@Suite("RepositoryViewModel — stash of selected files", .serialized)
@MainActor
struct RepositoryViewModelStashSelectedTests {

    @Test("Stashes only the picked files and refreshes the working copy")
    func stashesPickedFiles() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("init", files: ["a.txt": "a\n", "b.txt": "b\n"])
            try repo.write("a2\n", to: "a.txt")
            try repo.write("b2\n", to: "b.txt")
            try repo.write("new\n", to: "new.txt")
        }
        defer { repo.remove() }
        let vm = RepositoryViewModel(repository: Repository(url: repo.url))
        await vm.workingCopy.refreshStatus()
        let picked = vm.workingCopy.status.files.filter { $0.path != "b.txt" }

        #expect(await vm.stash(picked))

        #expect(vm.workingCopy.status.files.map(\.path) == ["b.txt"])
        #expect(vm.stashes.count == 1)
        #expect(vm.commitError == nil)
    }

    @Test("Refused while another operation runs, and with nothing picked")
    func guards() async {
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        let vm = RepositoryViewModel(repository: Repository(url: url))
        let file = WorkingCopyFile(path: "a.txt", stagedStatus: .unmodified,
                                   unstagedStatus: .modified, originalPath: nil)
        #expect(await vm.stash([]) == false)
        vm.isMutating = true
        #expect(await vm.stash([file]) == false)
        #expect(vm.commitError == nil)
    }
}

@Suite("RepositoryViewModel — stashes changed from the shell", .serialized)
@MainActor
struct RepositoryViewModelShellStashTests {

    private static func stashSubjects(in vm: RepositoryViewModel) -> [String] {
        vm.history.commits.map(\.subject).filter { $0.hasPrefix("On main:") }
    }

    @Test("A stash pushed or dropped from the shell shows up or goes away on the next watcher refresh, keeping the pages")
    func shellStashesReload() async throws {
        let repo = try await GitTestRepo.make { repo in
            for index in 0..<5 { try repo.commit("c\(index)", files: ["a.txt": "v\(index)\n"]) }
        }
        defer { repo.remove() }
        let vm = RepositoryViewModel(repository: Repository(url: repo.url))
        vm.history.pageSize = { 2 }
        await vm.loadRefs()
        await vm.history.loadInitial()
        let last = try #require(vm.history.commits.last)
        await vm.history.loadMoreIfNeeded(currentItem: last)
        let deepest = try #require(vm.history.commits.last)
        #expect(deepest.subject == "c1" && vm.history.loadedRawCount == 4)
        #expect(Self.stashSubjects(in: vm).isEmpty)

        // A push from the shell: the new stash is a row, and the pages loaded before still are.
        try repo.write("one\n", to: "a.txt")
        try await repo.gitAsync("stash", "push", "-q", "-m", "one")
        await vm.refreshFromExternalChange()
        #expect(Self.stashSubjects(in: vm) == ["On main: one"])
        #expect(vm.history.commits.contains { $0.id == deepest.id })
        #expect(vm.history.hasMore)

        // A drop of a stash that isn't the last one only rewrites its reflog.
        try repo.write("two\n", to: "a.txt")
        try await repo.gitAsync("stash", "push", "-q", "-m", "two")
        try await repo.gitAsync("stash", "drop", "-q", "stash@{1}")
        await vm.refreshFromExternalChange()
        #expect(Self.stashSubjects(in: vm) == ["On main: two"])
        #expect(vm.history.commits.contains { $0.id == deepest.id })

        try await repo.gitAsync("stash", "drop", "-q")
        await vm.refreshFromExternalChange()
        #expect(Self.stashSubjects(in: vm).isEmpty)
        #expect(vm.history.commits.contains { $0.id == deepest.id })
    }
}
