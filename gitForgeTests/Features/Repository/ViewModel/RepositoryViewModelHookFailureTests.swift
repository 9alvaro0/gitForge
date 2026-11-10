import Foundation
import Testing
@testable import gitForge

/// A local hook stopping a commit or a `--continue` raises the hook sheet
/// with its full output, keeps the composer, and Retry / Commit without
/// hooks run it again (#58). Real git and real hooks.
@Suite("RepositoryViewModel — hook failures", .serialized)
@MainActor
struct RepositoryViewModelHookFailureTests {

    private static let failingPreCommit = "echo 'lint: 2 problems'\necho 'src/a.js:1 no-var' >&2\nexit 1"

    /// A repo with one commit and a staged change, the VM loaded on it.
    private static func makeStaged() async throws -> (GitTestRepo, RepositoryViewModel) {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("first", files: ["a.txt": "1"])
            try repo.write("2", to: "a.txt")
            try repo.git("add", "a.txt")
        }
        let vm = RepositoryViewModel(repository: Repository(url: repo.url))
        await vm.workingCopy.refreshStatus()
        vm.workingCopy.commitSubject = "feat: thing"
        vm.workingCopy.commitBody = "Longer body."
        return (repo, vm)
    }

    private static func headSubject(_ repo: GitTestRepo) async throws -> String {
        try await repo.gitAsync("log", "-1", "--format=%s").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test("A failing pre-commit raises the sheet with its full output and keeps the message")
    func failingCommitRaisesSheet() async throws {
        let (repo, vm) = try await Self.makeStaged()
        defer { repo.remove() }
        try await repo.installHookAsync("pre-commit", script: Self.failingPreCommit)

        let ok = await vm.commit()

        #expect(!ok)
        let failure = try #require(vm.hookFailure)
        #expect(failure.hookName == "pre-commit")
        #expect(failure.output.contains("lint: 2 problems"))
        #expect(failure.output.contains("src/a.js:1 no-var"))
        #expect(failure.canSkipHooks)
        #expect(vm.commitError == failure.summary)
        let message = vm.commitError ?? ""
        #expect(!message.lowercased().contains("remote"), "\(message)")
        #expect(vm.workingCopy.commitSubject == "feat: thing")
        #expect(vm.workingCopy.commitBody == "Longer body.")
        #expect(try await Self.headSubject(repo) == "first")
    }

    @Test("Retry runs the hook again and commits once it passes")
    func retryCommits() async throws {
        let (repo, vm) = try await Self.makeStaged()
        defer { repo.remove() }
        try await repo.installHookAsync("pre-commit", script: Self.failingPreCommit)
        _ = await vm.commit()
        let failure = try #require(vm.hookFailure)

        // Retry while it still fails: a fresh sheet, still nothing committed.
        await vm.retry(failure)
        let second = try #require(vm.hookFailure)
        #expect(second.id != failure.id)
        #expect(try await Self.headSubject(repo) == "first")

        try await repo.installHookAsync("pre-commit", script: "exit 0")
        await vm.retry(second)

        #expect(vm.hookFailure == nil)
        #expect(vm.commitError == nil)
        #expect(try await Self.headSubject(repo) == "feat: thing")
        #expect(vm.workingCopy.commitSubject.isEmpty)
    }

    @Test("Commit without hooks commits past the failing hook")
    func commitWithoutHooks() async throws {
        let (repo, vm) = try await Self.makeStaged()
        defer { repo.remove() }
        try await repo.installHookAsync("pre-commit", script: Self.failingPreCommit)
        _ = await vm.commit()
        let failure = try #require(vm.hookFailure)

        await vm.retry(failure, skipHooks: true)

        #expect(vm.hookFailure == nil)
        #expect(try await Self.headSubject(repo) == "feat: thing")
    }

    @Test("A commit failure without hooks stays an inline error")
    func noHooksNoSheet() async throws {
        let (repo, vm) = try await Self.makeStaged()
        defer { repo.remove() }
        // An index lock makes git fail on its own.
        try await repo.perform { try $0.write("", to: ".git/index.lock") }

        let ok = await vm.commit()

        #expect(!ok)
        #expect(vm.hookFailure == nil)
        #expect(vm.commitError?.contains("index.lock") == true)
        #expect(vm.workingCopy.commitSubject == "feat: thing")
    }

    @Test("A failing hook on merge --continue raises the sheet without the skip option")
    func continueMergeHookFailure() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("base", files: ["f.txt": "base\n"])
            try repo.git("checkout", "-q", "-b", "other")
            try repo.commit("theirs", files: ["f.txt": "theirs\n"])
            try repo.git("checkout", "-q", "main")
            try repo.commit("ours", files: ["f.txt": "ours\n"])
            _ = try repo.git(["merge", "other"], allowFailure: true)
            try repo.write("resolved\n", to: "f.txt")
            try repo.git("add", "f.txt")
        }
        defer { repo.remove() }
        try await repo.installHookAsync("pre-commit", script: "echo 'merge check failed' >&2\nexit 1")
        let vm = RepositoryViewModel(repository: Repository(url: repo.url))
        await vm.loadConflictState()
        #expect(vm.mergeState == .merging)

        await vm.continueMerge()

        let failure = try #require(vm.hookFailure)
        #expect(failure.operation == .continueIntegration(.merging))
        #expect(!failure.canSkipHooks)
        #expect(failure.output.contains("merge check failed"))
        #expect(repo.exists(".git/MERGE_HEAD"))

        try await repo.installHookAsync("pre-commit", script: "exit 0")
        await vm.retry(failure)
        #expect(vm.hookFailure == nil)
        #expect(!repo.exists(".git/MERGE_HEAD"))
    }
}
