import Foundation
import Testing
@testable import gitForge

/// The undo the view model offers after each destructive operation: what it
/// records, what withdraws it, and what running it does, with real git.
@Suite("RepositoryViewModel — undo", .serialized)
@MainActor
struct RepositoryViewModelUndoTests {

    private static func sha(_ repo: GitTestRepo, _ ref: String) async throws -> String {
        try await repo.gitAsync("rev-parse", ref).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func makeRepo() async throws -> GitTestRepo {
        try await GitTestRepo.make { repo in
            try repo.commit("first", files: ["a.txt": "1\n"])
            try repo.git("branch", "feature")
            try repo.commit("second", files: ["a.txt": "2\n"])
        }
    }

    private static func loadedVM(_ repo: GitTestRepo) async -> RepositoryViewModel {
        let vm = RepositoryViewModel(repository: Repository(url: repo.url))
        await vm.loadRefs()
        await vm.workingCopy.refreshStatus()
        return vm
    }

    @Test("A hard reset offers its undo, and running it brings back the commit and the lost change")
    func resetAndUndo() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        try await repo.externalWriteAsync("dirty\n", to: "a.txt")
        let vm = await Self.loadedVM(repo)
        let before = try await Self.sha(repo, "HEAD")

        #expect(await vm.reset(to: try await Self.sha(repo, "HEAD~1"), mode: .hard) == .clean)
        let entry = try #require(vm.undo.pending)
        #expect(entry.menuTitle == "Undo Reset of main")

        let outcome = await vm.performUndo(id: entry.id)
        #expect(outcome == .undone("main is back at \(before.prefix(7))"))
        #expect(try await Self.sha(repo, "HEAD") == before)
        #expect(repo.read("a.txt") == "dirty\n")
        #expect(vm.undo.pending == nil)
        #expect(!vm.isMutating)
        // The working copy shows the change again.
        #expect(vm.workingCopy.status.files.map(\.path) == ["a.txt"])
    }

    @Test("The next mutating operation withdraws the undo; a stale toast's id is refused")
    func nextOperationWithdraws() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        let vm = await Self.loadedVM(repo)
        let feature = try #require(vm.localBranches.first { $0.name == "feature" })
        try await vm.deleteBranch(feature, force: true).get()
        let entry = try #require(vm.undo.pending)

        try await repo.externalWriteAsync("3\n", to: "a.txt")
        await vm.workingCopy.refreshStatus()
        await vm.stage(vm.workingCopy.status.files)
        #expect(vm.undo.pending == nil)

        let outcome = await vm.performUndo(id: entry.id)
        #expect(outcome == .refused("That can no longer be undone."))
        #expect(await vm.performUndo() == .refused("That can no longer be undone."))
    }

    @Test("Undo after an external change is refused, not applied, and is no longer offered")
    func refusedAfterExternalChange() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        let vm = await Self.loadedVM(repo)
        let feature = try #require(vm.localBranches.first { $0.name == "feature" })
        let main = try await Self.sha(repo, "main")
        try await vm.moveBranch(feature, to: main).get()
        #expect(vm.undo.pending?.menuTitle == "Undo Move of feature")

        // Moved again from the terminal.
        try await repo.gitAsync("branch", "-f", "feature", "HEAD~1")
        let outcome = await vm.performUndo()
        #expect(outcome == .refused("Can't undo: feature has moved since."))
        #expect(try await Self.sha(repo, "feature") == Self.sha(repo, "HEAD~1"))
        #expect(vm.undo.pending == nil)
    }

    @Test("Deleting a branch and dropping a stash can each be undone from the view model")
    func deleteAndDropUndo() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        try await repo.externalWriteAsync("wip\n", to: "a.txt")
        try await repo.gitAsync("stash", "push", "-q", "-m", "keep me")
        let vm = await Self.loadedVM(repo)
        let tip = try await Self.sha(repo, "feature")

        let feature = try #require(vm.localBranches.first { $0.name == "feature" })
        try await vm.deleteBranch(feature, force: true).get()
        #expect(await vm.performUndo() == .undone("Restored branch feature"))
        #expect(try await Self.sha(repo, "feature") == tip)
        #expect(vm.localBranches.contains { $0.name == "feature" })

        let stash = try #require(vm.stashes.first)
        try await vm.dropStash(stash).get()
        #expect(vm.stashes.isEmpty)
        #expect(await vm.performUndo() == .undone("Restored the stash"))
        #expect(vm.stashes.map(\.sha) == [stash.sha])
    }

    @Test("Discarding publishes a toast with Undo for the tracked file and says where the untracked one went")
    func discardToastAndUndo() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        try await repo.externalWriteAsync("edited\n", to: "a.txt")
        try await repo.externalWriteAsync("scratch\n", to: "new.txt")
        let vm = await Self.loadedVM(repo)

        await vm.discardChanges(vm.workingCopy.status.files)
        let entry = try #require(vm.undo.pending)
        let success = try #require(vm.operationSuccess)
        #expect(success.undoID == entry.id)
        // The Trash where the volume has one, else deleted — and the toast says which.
        #expect(success.message == "Discarded changes in 1 file. Moved 1 untracked file to the Trash"
            || success.message == "Discarded changes in 1 file. Deleted 1 untracked file (its disk has no Trash)")
        #expect(!repo.exists("new.txt"))

        #expect(await vm.performUndo(id: entry.id) == .undone("Restored the discarded changes"))
        #expect(repo.read("a.txt") == "edited\n")
        #expect(!repo.exists("new.txt"))
    }

    @Test("Discarding only untracked files offers no undo")
    func untrackedOnlyDiscardOffersNothing() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        try await repo.externalWriteAsync("scratch\n", to: "new.txt")
        let vm = await Self.loadedVM(repo)

        await vm.discardChanges(vm.workingCopy.status.files)
        #expect(vm.undo.pending == nil)
        #expect(vm.operationSuccess?.undoID == nil)
    }

    @Test("Discarding a hunk offers its undo")
    func hunkDiscardUndo() async throws {
        let base = (1...12).map(String.init).joined(separator: "\n") + "\n"
        let edited = base.replacingOccurrences(of: "\n2\n", with: "\nA\n")
            .replacingOccurrences(of: "\n11\n", with: "\nB\n")
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("base", files: ["f.txt": base])
            try repo.write(edited, to: "f.txt")
        }
        defer { repo.remove() }
        let vm = await Self.loadedVM(repo)
        let file = try #require(vm.workingCopy.status.files.first)
        vm.workingCopy.select(file, side: .unstaged)
        await vm.workingCopy.loadWorkingCopyDiff(file: file)
        let hunk = try #require(vm.workingCopy.workingCopyDiff.first)

        await vm.apply(.discard, hunk: hunk, in: file)
        #expect(repo.read("f.txt") != edited)
        let entry = try #require(vm.undo.pending)
        #expect(vm.operationSuccess?.message == "Discarded the hunk")
        #expect(vm.operationSuccess?.undoID == entry.id)

        #expect(await vm.performUndo() == .undone("Restored the discarded changes"))
        #expect(repo.read("f.txt") == edited)
    }

    @Test("A force-push offers its undo on the toast; running it puts the remote branch back")
    func forcePushUndo() async throws {
        let origin = try await GitTestRepo.make(bare: true)
        let work = try await GitTestRepo.make { repo in
            try repo.commit("first", files: ["a.txt": "1\n"])
            try repo.commit("second", files: ["a.txt": "2\n"])
            try repo.git("remote", "add", "origin", origin.url.path)
            try repo.git("push", "-q", "-u", "origin", "main")
            try repo.git("commit", "-q", "--amend", "-m", "second, reworded")
        }
        defer { origin.remove(); work.remove() }
        let previous = try await Self.sha(origin, "main")
        let vm = await Self.loadedVM(work)

        #expect(await vm.push(forceWithLease: true))
        let pushed = try await Self.sha(work, "main")
        #expect(try await Self.sha(origin, "main") == pushed)
        let entry = try #require(vm.undo.pending)
        #expect(entry.operation == .forcePush(remote: "origin", branch: "main", pushed: pushed, previous: previous))
        #expect(entry.menuTitle == "Undo Force-Push to origin/main")
        #expect(vm.operationSuccess?.undoID == entry.id)

        #expect(await vm.performUndo(id: entry.id) == .undone("origin/main is back at \(previous.prefix(7))"))
        #expect(try await Self.sha(origin, "main") == previous)
        #expect(vm.remoteOperation == nil)
        // The local branch keeps the rewritten commit, now ahead of and behind the remote.
        #expect(vm.aheadCount == 1 && vm.behindCount == 1)
    }

    @Test("A plain push offers nothing and withdraws what was on offer")
    func plainPushWithdraws() async throws {
        let origin = try await GitTestRepo.make(bare: true)
        let work = try await GitTestRepo.make { repo in
            try repo.commit("first", files: ["a.txt": "1\n"])
            try repo.git("branch", "feature")
            try repo.git("remote", "add", "origin", origin.url.path)
            try repo.git("push", "-q", "-u", "origin", "main")
            try repo.commit("second", files: ["a.txt": "2\n"])
        }
        defer { origin.remove(); work.remove() }
        let vm = await Self.loadedVM(work)
        let feature = try #require(vm.localBranches.first { $0.name == "feature" })
        try await vm.deleteBranch(feature, force: true).get()
        #expect(vm.undo.pending != nil)

        #expect(await vm.push())
        #expect(vm.undo.pending == nil)
        #expect(vm.operationSuccess?.undoID == nil)
    }
}
