import Foundation
import Testing
@testable import gitForge

@Suite("RepositoryViewModel — stash or discard what blocks a checkout", .serialized)
@MainActor
struct RepositoryViewModelBlockedCheckoutTests {

    /// `main` and `feature`, checked out on `main`. `feature` changes
    /// `a.txt` and `staged.txt` and adds `n.txt`; `keep.txt` is the same on
    /// both.
    private static func makeRepo() async throws -> GitTestRepo {
        try await GitTestRepo.make { repo in
            try repo.commit("base", files: ["a.txt": "a\n", "staged.txt": "s\n", "keep.txt": "keep\n"])
            try repo.git("checkout", "-q", "-b", "feature")
            try repo.commit("feature", files: ["a.txt": "feature\n", "staged.txt": "s2\n", "n.txt": "theirs\n"])
            try repo.git("checkout", "-q", "main")
        }
    }

    /// Changes in the way of `feature` — `a.txt` modified, `staged.txt`
    /// staged, `n.txt` untracked — and one that isn't, `keep.txt`.
    private static func dirty(_ repo: GitTestRepo) async throws {
        try await repo.externalWriteAsync("local\n", to: "a.txt")
        try await repo.externalWriteAsync("staged-local\n", to: "staged.txt")
        try await repo.gitAsync("add", "staged.txt")
        try await repo.externalWriteAsync("mine\n", to: "n.txt")
        try await repo.externalWriteAsync("keep-local\n", to: "keep.txt")
    }

    private static func makeVM(_ repo: GitTestRepo) async -> RepositoryViewModel {
        let vm = RepositoryViewModel(repository: Repository(url: repo.url))
        await vm.loadRefs()
        return vm
    }

    private static func localBranch(_ name: String, in vm: RepositoryViewModel) throws -> GitRef {
        try #require(vm.refs.first { $0.isLocalBranch && $0.name == name })
    }

    @Test("A checkout blocked by local changes asks about exactly the files in the way")
    func blockedCheckoutAsks() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        try await Self.dirty(repo)
        let vm = await Self.makeVM(repo)
        let feature = try Self.localBranch("feature", in: vm)

        #expect(await vm.checkout(.branch(feature)) == .blocked)

        let request = try #require(vm.blockedCheckout)
        #expect(request.files.map(\.path).sorted() == ["a.txt", "n.txt", "staged.txt"])
        #expect(request.target == .branch(feature))
        #expect(vm.currentBranchName == "main")
        #expect(repo.read("a.txt") == "local\n", "nothing is touched before the user picks")
    }

    @Test("Discarding drops only those files' changes, checks out and carries the rest along")
    func confirmDiscardsAndChecksOut() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        try await Self.dirty(repo)
        let vm = await Self.makeVM(repo)
        _ = await vm.checkout(.branch(try Self.localBranch("feature", in: vm)))
        let request = try #require(vm.blockedCheckout)

        #expect(await vm.discardBlockingChangesAndCheckout(request) == .done("Checked out feature"))

        #expect(vm.blockedCheckout == nil)
        #expect(vm.currentBranchName == "feature")
        #expect(repo.read("a.txt") == "feature\n")
        #expect(repo.read("staged.txt") == "s2\n")
        #expect(repo.read("n.txt") == "theirs\n")
        #expect(try repo.porcelain() == [" M keep.txt"], "a change that wasn't in the way comes along")
        #expect(repo.read("keep.txt") == "keep-local\n")
    }

    @Test("Stashing keeps only those files' changes in a stash, checks out and carries the rest along")
    func stashAndCheckOut() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        try await Self.dirty(repo)
        let vm = await Self.makeVM(repo)
        _ = await vm.checkout(.branch(try Self.localBranch("feature", in: vm)))
        let blocked = try #require(vm.blockedCheckout)

        #expect(await vm.stashBlockingChangesAndCheckout(blocked)
                == .done("Checked out feature. Your changes are in Stashes."))

        #expect(vm.blockedCheckout == nil)
        #expect(vm.currentBranchName == "feature")
        #expect(repo.read("a.txt") == "feature\n")
        #expect(repo.read("n.txt") == "theirs\n")
        #expect(try repo.porcelain() == [" M keep.txt"], "a change that wasn't in the way comes along")
        #expect(vm.stashes.count == 1)
        #expect(try await repo.gitAsync("stash", "list", "--format=%gs") == "On main: Before checking out feature\n")
        let stashed = try await repo.gitAsync("stash", "show", "--include-untracked", "--name-only", "stash@{0}")
        #expect(stashed.split(separator: "\n").sorted() == ["a.txt", "n.txt", "staged.txt"])

        // Back on main the stash gives every change back, staged ones staged.
        try await repo.gitAsync("checkout", "-q", "main")
        try await repo.gitAsync("stash", "pop", "-q", "--index")
        #expect(repo.read("a.txt") == "local\n")
        #expect(repo.read("n.txt") == "mine\n")
        #expect(try repo.porcelain() == [" M a.txt", " M keep.txt", "?? n.txt", "M  staged.txt"])
    }

    @Test("Stashing is refused while another local operation runs")
    func stashGuard() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        try await Self.dirty(repo)
        let vm = await Self.makeVM(repo)
        _ = await vm.checkout(.branch(try Self.localBranch("feature", in: vm)))
        let blocked = try #require(vm.blockedCheckout)
        vm.isMutating = true

        #expect(await vm.stashBlockingChangesAndCheckout(blocked) == .failed(GitError.busy.userMessage))

        vm.isMutating = false
        #expect(try await repo.gitAsync("stash", "list").isEmpty, "nothing is stashed")
        #expect(vm.currentBranchName == "main")
    }

    @Test("Changes that aren't in the way don't ask: git carries them to the branch")
    func unblockedCheckout() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        try await repo.externalWriteAsync("keep-local\n", to: "keep.txt")
        let vm = await Self.makeVM(repo)

        #expect(await vm.checkout(.branch(try Self.localBranch("feature", in: vm))) == .done("Checked out feature"))

        #expect(vm.blockedCheckout == nil)
        #expect(vm.currentBranchName == "feature")
        #expect(try repo.porcelain() == [" M keep.txt"])
    }

    @Test("A commit checkout blocked by local changes asks, then detaches HEAD there")
    func commitCheckout() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        let sha = try await repo.gitAsync("rev-parse", "feature").trimmingCharacters(in: .whitespacesAndNewlines)
        try await repo.externalWriteAsync("local\n", to: "a.txt")
        let vm = await Self.makeVM(repo)

        #expect(await vm.checkout(.commit(sha: sha)) == .blocked)
        let request = try #require(vm.blockedCheckout)
        #expect(request.files.map(\.path) == ["a.txt"])

        #expect(await vm.discardBlockingChangesAndCheckout(request) == .done("Detached HEAD at \(sha.prefix(7))"))

        #expect(vm.currentBranchName == nil)
        #expect(vm.headSha == sha)
        #expect(try repo.porcelain().isEmpty)
    }

    @Test("A pull request branch only on the remote is created tracking it once the changes are discarded")
    func pullRequestBranch() async throws {
        let origin = try await GitTestRepo.make(bare: true)
        let repo = try await Self.makeRepo()
        defer {
            origin.remove()
            repo.remove()
        }
        try await repo.gitAsync("remote", "add", "origin", origin.url.path)
        try await repo.gitAsync("push", "-q", "origin", "main", "feature")
        try await repo.gitAsync("branch", "-q", "-D", "feature")
        try await repo.gitAsync("fetch", "-q", "origin")
        try await repo.externalWriteAsync("local\n", to: "a.txt")
        let vm = await Self.makeVM(repo)

        #expect(await vm.checkout(.pullRequestBranch("feature")) == .blocked)
        let request = try #require(vm.blockedCheckout)
        #expect(request.files.map(\.path) == ["a.txt"])

        #expect(await vm.discardBlockingChangesAndCheckout(request) == .done("Checked out feature"))

        #expect(vm.currentBranchName == "feature")
        let upstream = try await repo.gitAsync("rev-parse", "--abbrev-ref", "feature@{upstream}")
        #expect(upstream == "origin/feature\n")
    }

    @Test("A checkout that fails for another reason reports it and asks nothing")
    func otherFailureStillReports() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        let vm = await Self.makeVM(repo)
        let missing = GitRef(name: "missing", kind: .localBranch, targetSha: "deadbeef", isHead: false)

        guard case .failed = await vm.checkout(.branch(missing)) else {
            Issue.record("expected a failure")
            return
        }
        #expect(vm.blockedCheckout == nil)
    }

    @Test("A rebase by drop that has to check out first fails as before, without asking")
    func rebaseDoesNotAsk() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        try await Self.dirty(repo)
        let vm = await Self.makeVM(repo)
        let feature = try Self.localBranch("feature", in: vm)
        let main = try Self.localBranch("main", in: vm)

        guard case .failed = await vm.rebase(feature, onto: main) else {
            Issue.record("expected the rebase to fail")
            return
        }
        #expect(vm.blockedCheckout == nil, "discarding would only switch, not rebase")
        #expect(repo.read("a.txt") == "local\n")
    }

    @Test("Confirming is refused while another local operation runs")
    func confirmGuard() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        try await Self.dirty(repo)
        let vm = await Self.makeVM(repo)
        _ = await vm.checkout(.branch(try Self.localBranch("feature", in: vm)))
        let request = try #require(vm.blockedCheckout)
        vm.isMutating = true

        #expect(await vm.discardBlockingChangesAndCheckout(request) == .failed(GitError.busy.userMessage))

        vm.isMutating = false
        #expect(repo.read("a.txt") == "local\n", "nothing is discarded")
        #expect(vm.currentBranchName == "main")
    }
}

@Suite("WorkspaceUI — checkout toasts")
@MainActor
struct WorkspaceUICheckoutToastTests {
    @Test("Done and failed checkouts toast; a blocked or cancelled one stays quiet")
    func toasts() {
        let ui = WorkspaceUI()

        ui.emitToast(for: .done("Checked out feature"))
        #expect(ui.activeToast?.message == "Checked out feature")
        #expect(ui.activeToast?.kind == .ok)

        ui.emitToast(for: .failed("boom"))
        #expect(ui.activeToast?.message == "boom")
        #expect(ui.activeToast?.kind == .error)

        ui.activeToast = nil
        ui.emitToast(for: .blocked)
        ui.emitToast(for: .cancelled)
        #expect(ui.activeToast == nil)
    }
}
