import Foundation
import Testing
@testable import gitForge

/// Each destructive operation with its undo, against real git: recorded the
/// way the view model records it, applied with `performUndo`, and refused
/// when the repository moved on in between.
@Suite("GitCLI undo", .serialized)
struct GitCLIUndoTests {

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sha(_ repo: GitTestRepo, _ ref: String) async throws -> String {
        trimmed(try await repo.gitAsync("rev-parse", ref))
    }

    /// Two commits on main, and a dirty tree: a staged change and a further
    /// unstaged one to `b.txt`, an unstaged change to `a.txt`, a staged new
    /// file and an untracked one.
    private static func makeDirtyRepo() async throws -> GitTestRepo {
        try await GitTestRepo.make { repo in
            try repo.commit("first", files: ["a.txt": "a1\n", "b.txt": "b1\n"])
            try repo.commit("second", files: ["a.txt": "a2\n"])
            try repo.write("b staged\n", to: "b.txt")
            try repo.git("add", "b.txt")
            try repo.write("b worktree\n", to: "b.txt")
            try repo.write("a worktree\n", to: "a.txt")
            try repo.write("new\n", to: "c.txt")
            try repo.git("add", "c.txt")
            try repo.write("untracked\n", to: "u.txt")
        }
    }

    private static let dirtyPorcelain = [" M a.txt", "?? u.txt", "A  c.txt", "MM b.txt"].sorted()

    private static func reset(_ repo: GitTestRepo, to ref: String, mode: GitCLI.ResetMode) async throws -> UndoOperation? {
        let cli = repo.cli
        let target = try await sha(repo, ref)
        let capture = try #require(await cli.captureReset(mode: mode))
        try await cli.reset(to: target, mode: mode)
        return await cli.resetUndo(after: capture)
    }

    // MARK: Reset

    @Test("A hard reset comes back with its commits and the staged and unstaged changes it threw away")
    func undoHardReset() async throws {
        let repo = try await Self.makeDirtyRepo()
        defer { repo.remove() }
        let before = try await Self.sha(repo, "HEAD")

        let undo = try #require(try await Self.reset(repo, to: "HEAD~1", mode: .hard))
        #expect(try await repo.porcelainAsync() == ["?? u.txt"])

        try await repo.cli.performUndo(undo)

        #expect(try await Self.sha(repo, "HEAD") == before)
        #expect(await repo.cli.currentBranchName() == "main")
        #expect(try await repo.porcelainAsync() == Self.dirtyPorcelain)
        #expect(repo.read("a.txt") == "a worktree\n")
        #expect(repo.read("b.txt") == "b worktree\n")
        #expect(try await repo.gitAsync("show", ":b.txt") == "b staged\n")
    }

    @Test("A hard reset to HEAD (discard everything) can be undone too")
    func undoHardResetToHead() async throws {
        let repo = try await Self.makeDirtyRepo()
        defer { repo.remove() }

        let undo = try #require(try await Self.reset(repo, to: "HEAD", mode: .hard))
        try await repo.cli.performUndo(undo)

        #expect(try await repo.porcelainAsync() == Self.dirtyPorcelain)
    }

    @Test("A mixed reset comes back with the index it unstaged; a soft one just moves HEAD back")
    func undoMixedAndSoftReset() async throws {
        let repo = try await Self.makeDirtyRepo()
        defer { repo.remove() }
        let before = try await Self.sha(repo, "HEAD")

        let mixed = try #require(try await Self.reset(repo, to: "HEAD~1", mode: .mixed))
        try await repo.cli.performUndo(mixed)
        #expect(try await Self.sha(repo, "HEAD") == before)
        #expect(try await repo.porcelainAsync() == Self.dirtyPorcelain)

        let soft = try #require(try await Self.reset(repo, to: "HEAD~1", mode: .soft))
        try await repo.cli.performUndo(soft)
        #expect(try await Self.sha(repo, "HEAD") == before)
        #expect(try await repo.porcelainAsync() == Self.dirtyPorcelain)
    }

    @Test("A soft reset to HEAD changes nothing and offers no undo")
    func noOpResetOffersNothing() async throws {
        let repo = try await Self.makeDirtyRepo()
        defer { repo.remove() }
        #expect(try await Self.reset(repo, to: "HEAD", mode: .soft) == nil)
    }

    @Test("Undoing a reset is refused once HEAD moved, or once there are changes a hard undo would overwrite")
    func resetRefusals() async throws {
        let repo = try await Self.makeDirtyRepo()
        defer { repo.remove() }
        let undo = try #require(try await Self.reset(repo, to: "HEAD~1", mode: .hard))

        try await repo.externalWriteAsync("edited since\n", to: "a.txt")
        await #expect(throws: UndoRefusal.changesSinceReset) { try await repo.cli.performUndo(undo) }
        #expect(repo.read("a.txt") == "edited since\n")

        try await repo.gitAsync("checkout", "--", "a.txt")
        try await repo.commitAsync("made since")
        let moved = try await Self.sha(repo, "HEAD")
        await #expect(throws: UndoRefusal.headMoved("main")) { try await repo.cli.performUndo(undo) }
        #expect(try await Self.sha(repo, "HEAD") == moved)
    }

    // MARK: Move branch tip

    @Test("A moved branch tip goes back, and not once it moved again or got checked out")
    func undoMoveBranch() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("first")
            try repo.git("branch", "feature")
            try repo.commit("second")
        }
        defer { repo.remove() }
        let cli = repo.cli
        let previous = try await Self.sha(repo, "feature")
        let target = try await Self.sha(repo, "main")
        try await cli.forceUpdateBranch("feature", to: target)
        let undo = UndoOperation.moveBranch(name: "feature", movedTo: target, previous: previous)

        try await cli.performUndo(undo)
        #expect(try await Self.sha(repo, "feature") == previous)

        // Moved again (outside the app) since: refused, left alone.
        try await cli.forceUpdateBranch("feature", to: target)
        try await repo.gitAsync("branch", "-f", "feature", previous)
        await #expect(throws: UndoRefusal.branchMoved("feature")) { try await cli.performUndo(undo) }

        try await cli.forceUpdateBranch("feature", to: target)
        try await repo.gitAsync("checkout", "-q", "feature")
        await #expect(throws: UndoRefusal.branchCheckedOut("feature")) { try await cli.performUndo(undo) }
        #expect(try await Self.sha(repo, "feature") == target)
    }

    // MARK: Delete branch

    @Test("A deleted branch comes back at its tip with its upstream config")
    func undoDeleteBranch() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("first")
            try repo.git("checkout", "-q", "-b", "feat/x.1")
            try repo.commit("on feature")
            try repo.git("checkout", "-q", "main")
            try repo.git("config", "branch.feat/x.1.remote", "origin")
            try repo.git("config", "branch.feat/x.1.merge", "refs/heads/feat/x.1")
            // Same prefix, other branch: must not be captured.
            try repo.git("config", "branch.feat/x21.remote", "elsewhere")
        }
        defer { repo.remove() }
        let cli = repo.cli
        let tip = try await Self.sha(repo, "feat/x.1")

        let undo = try #require(await cli.captureBranchDeletion("feat/x.1"))
        #expect(undo == .deleteBranch(name: "feat/x.1", sha: tip, config: [
            .init(key: "branch.feat/x.1.remote", value: "origin"),
            .init(key: "branch.feat/x.1.merge", value: "refs/heads/feat/x.1"),
        ]))
        try await cli.deleteBranch("feat/x.1", force: true)

        try await cli.performUndo(undo)
        #expect(try await Self.sha(repo, "feat/x.1") == tip)
        #expect(Self.trimmed(try await repo.gitAsync("config", "branch.feat/x.1.merge")) == "refs/heads/feat/x.1")
        #expect(Self.trimmed(try await repo.gitAsync("config", "branch.feat/x21.remote")) == "elsewhere")
    }

    @Test("Undoing a delete is refused when a branch with that name exists again")
    func undoDeleteRefusedWhenRecreated() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("first")
            try repo.git("branch", "feature")
            try repo.commit("second")
        }
        defer { repo.remove() }
        let cli = repo.cli
        let undo = try #require(await cli.captureBranchDeletion("feature"))
        try await cli.deleteBranch("feature", force: true)
        try await repo.gitAsync("branch", "feature")
        let recreated = try await Self.sha(repo, "feature")

        await #expect(throws: UndoRefusal.branchExists("feature")) { try await cli.performUndo(undo) }
        #expect(try await Self.sha(repo, "feature") == recreated)
    }

    // MARK: Drop stash

    @Test("A dropped stash comes back with its message, and only once")
    func undoDropStash() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("first", files: ["a.txt": "1\n"])
            try repo.write("2\n", to: "a.txt")
            try repo.git("stash", "push", "-q", "-m", "work in progress")
        }
        defer { repo.remove() }
        let cli = repo.cli
        let stash = try #require(try await cli.stashes().first)
        try await cli.stashDrop(sha: stash.sha)
        #expect(try await cli.stashes().isEmpty)
        let undo = UndoOperation.dropStash(sha: stash.sha, message: stash.subject)

        try await cli.performUndo(undo)
        let restored = try await cli.stashes()
        #expect(restored.map(\.sha) == [stash.sha])
        #expect(restored.first?.subject == stash.subject)
        #expect(stash.subject.hasSuffix("work in progress"))

        await #expect(throws: UndoRefusal.stashAlreadyListed) { try await cli.performUndo(undo) }
    }

    // MARK: Discard

    @Test("Discarded unstaged changes come back, staged ones and the index untouched; deletions too")
    func undoDiscard() async throws {
        let repo = try await Self.makeDirtyRepo()
        defer { repo.remove() }
        try await repo.perform { try FileManager.default.removeItem(at: $0.url.appendingPathComponent("c.txt")) }
        let cli = repo.cli
        let before = try await repo.porcelainAsync()
        let paths = ["a.txt", "b.txt", "c.txt"]

        let snapshot = try await cli.snapshotWorkingTree()
        try await cli.discardChanges(paths: paths)
        #expect(try await repo.porcelainAsync() == ["?? u.txt", "A  c.txt", "M  b.txt"].sorted())
        let undo = try #require(await cli.discardUndo(snapshot: snapshot, paths: paths))

        try await cli.performUndo(undo)
        #expect(try await repo.porcelainAsync() == before)
        #expect(repo.read("b.txt") == "b worktree\n")
        #expect(!repo.exists("c.txt"))
    }

    @Test("A discarded hunk comes back")
    func undoHunkDiscard() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("first", files: ["a.txt": "1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n"])
            try repo.write("one\n2\n3\n4\n5\n6\n7\n8\n9\nten\n", to: "a.txt")
        }
        defer { repo.remove() }
        let cli = repo.cli
        let diff = try await cli.diffUnstaged(file: "a.txt")
        let hunk = try #require(DiffParser.parse(diff).first)
        let patch = try #require(HunkPatch.make(path: "a.txt", hunk: hunk, selectedLineIds: nil, reverse: true))

        let snapshot = try await cli.snapshotWorkingTree()
        try await cli.apply(patch: patch, cached: false, reverse: true)
        #expect(repo.read("a.txt") == "1\n2\n3\n4\n5\n6\n7\n8\n9\nten\n")
        let undo = try #require(await cli.discardUndo(snapshot: snapshot, paths: ["a.txt"]))

        try await cli.performUndo(undo)
        #expect(repo.read("a.txt") == "one\n2\n3\n4\n5\n6\n7\n8\n9\nten\n")
    }

    @Test("Undoing a discard is refused once the file changed, and leaves it alone")
    func undoDiscardRefusedAfterEdit() async throws {
        let repo = try await Self.makeDirtyRepo()
        defer { repo.remove() }
        let cli = repo.cli
        let snapshot = try await cli.snapshotWorkingTree()
        try await cli.discardChanges(paths: ["a.txt"])
        let undo = try #require(await cli.discardUndo(snapshot: snapshot, paths: ["a.txt"]))
        try await repo.externalWriteAsync("typed since\n", to: "a.txt")

        await #expect(throws: UndoRefusal.filesChanged) { try await cli.performUndo(undo) }
        #expect(repo.read("a.txt") == "typed since\n")
    }

    // MARK: Force-push

    /// A bare remote with main at `second`, and a clone whose main was
    /// rewritten to `rewritten` and force-pushed over it.
    private static func makeForcePushed() async throws -> (origin: GitTestRepo, work: GitTestRepo, previous: String, pushed: String) {
        let origin = try await GitTestRepo.make(bare: true)
        let work = try await GitTestRepo.make { repo in
            try repo.commit("first", files: ["a.txt": "1\n"])
            try repo.commit("second", files: ["a.txt": "2\n"])
            try repo.git("remote", "add", "origin", origin.url.path)
            try repo.git("push", "-q", "-u", "origin", "main")
            try repo.git("reset", "-q", "--hard", "HEAD~1")
            try repo.commit("rewritten", files: ["a.txt": "3\n"])
        }
        let previous = try await sha(work, "origin/main")
        try await work.cli.push(setUpstream: false, remote: "origin", branch: "main", forceWithLease: true)
        let pushed = try await sha(work, "main")
        return (origin, work, previous, pushed)
    }

    @Test("A force-push is undone by pushing the previous SHA back")
    func undoForcePush() async throws {
        let (origin, work, previous, pushed) = try await Self.makeForcePushed()
        defer { origin.remove(); work.remove() }
        #expect(try await Self.sha(origin, "main") == pushed)

        try await work.cli.performUndo(.forcePush(remote: "origin", branch: "main", pushed: pushed, previous: previous))

        #expect(try await Self.sha(origin, "main") == previous)
        #expect(try await Self.sha(work, "origin/main") == previous)
        // The local branch keeps what was pushed.
        #expect(try await Self.sha(work, "main") == pushed)
    }

    @Test("Undoing a force-push is refused when the remote moved since, and the remote is left alone")
    func undoForcePushRefusedAfterRemoteMoved() async throws {
        let (origin, work, previous, pushed) = try await Self.makeForcePushed()
        let other = try await GitTestRepo.make()
        defer { origin.remove(); work.remove(); other.remove() }
        // Someone else pushes on top of the force-pushed branch.
        try await other.perform { repo in
            try repo.git("fetch", "-q", origin.url.path, "main")
            try repo.git("checkout", "-q", "-B", "main", "FETCH_HEAD")
            try repo.commit("theirs")
            try repo.git("push", "-q", origin.url.path, "main")
        }
        let theirs = try await Self.sha(other, "main")

        await #expect(throws: UndoRefusal.remoteMoved("origin/main")) {
            try await work.cli.performUndo(.forcePush(remote: "origin", branch: "main", pushed: pushed, previous: previous))
        }
        #expect(try await Self.sha(origin, "main") == theirs)
    }

    // MARK: Parsing

    @Test("Config entries parse from `git config -z`, including a key with no value")
    func parsesConfigEntries() {
        #expect(GitCLI.parseConfigEntries("branch.a.remote\norigin\0branch.a.flag\0branch.a.x\nline1\nline2\0") == [
            .init(key: "branch.a.remote", value: "origin"),
            .init(key: "branch.a.flag", value: ""),
            .init(key: "branch.a.x", value: "line1\nline2"),
        ])
        #expect(GitCLI.regexEscaped("feat/x.1+") == "feat\\/x\\.1\\+")
    }
}
