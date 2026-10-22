import Foundation
import Testing
@testable import gitForge

/// What a pull would bring, in the history graph (§3.1, §4.1): the scope with remote
/// branches, on real repositories.
@Suite("RepositoryViewModel — remote branches in the graph", .serialized)
@MainActor
struct RepositoryViewModelRemoteGraphTests {

    /// A bare `server`; `work`, with `commits` commits on `main` pushed to it and tracking
    /// `origin/main`; and `other`, another clone of the server that pushes to it.
    private struct Remotes {
        let server: GitTestRepo
        let work: GitTestRepo
        let other: GitTestRepo

        func remove() {
            server.remove()
            work.remove()
            other.remove()
        }

        /// `other` commits `subject` on its `main` and pushes it.
        func serverCommit(_ subject: String) async throws {
            try await other.gitAsync("commit", "-q", "--allow-empty", "-m", subject)
            try await other.gitAsync("push", "-q", "origin", "main")
        }
    }

    private static func makeRemotes(commits: Int = 1) async throws -> Remotes {
        let server = try await GitTestRepo.make(bare: true)
        let serverPath = server.url.path
        let work = try await GitTestRepo.make { repo in
            for index in 0..<commits {
                try repo.git("commit", "-q", "--allow-empty", "-m", "c\(index)")
            }
            try repo.git("remote", "add", "origin", serverPath)
            try repo.git("push", "-q", "-u", "origin", "main")
        }
        let other = try await GitTestRepo.make { repo in
            try repo.git("remote", "add", "origin", serverPath)
            try repo.git("fetch", "-q", "origin")
            try repo.git("checkout", "-q", "-B", "main", "origin/main")
        }
        return Remotes(server: server, work: work, other: other)
    }

    private static func row(_ subject: String, in vm: RepositoryViewModel) -> Int? {
        vm.history.commits.firstIndex { $0.subject == subject }
    }

    @Test("After a fetch, what a pull would bring is loaded and drawn as ghosts")
    func fetchLoadsGhosts() async throws {
        let remotes = try await Self.makeRemotes()
        defer { remotes.remove() }
        let vm = RepositoryViewModel(repository: Repository(url: remotes.work.url))
        await vm.loadRefs()
        await vm.history.loadInitial()
        try await remotes.serverCommit("server one")
        #expect(Self.row("server one", in: vm) == nil)

        #expect(await vm.fetch())
        let row = try #require(Self.row("server one", in: vm))
        #expect(vm.history.graphLayouts[row].node.isGhost)
        #expect(vm.history.loadedScope?.remoteTips.keys.sorted() == ["origin/main"])
    }

    @Test("Without a local main, origin/main is loaded as the trunk")
    func remoteTrunkLoaded() async throws {
        let remotes = try await Self.makeRemotes()
        defer { remotes.remove() }
        try await remotes.work.gitAsync("switch", "-q", "-c", "feature")
        try await remotes.work.gitAsync("commit", "-q", "--allow-empty", "-m", "feature one")
        try await remotes.work.gitAsync("branch", "-q", "-D", "main")
        try await remotes.work.gitAsync("remote", "set-head", "origin", "main")
        try await remotes.serverCommit("server one")
        let vm = RepositoryViewModel(repository: Repository(url: remotes.work.url))
        await vm.loadRefs()
        await vm.history.loadInitial()
        #expect(await vm.fetch())

        #expect(vm.remoteHeads == ["origin": "origin/main"])
        let row = try #require(Self.row("server one", in: vm))
        #expect(vm.history.graphLayouts[row].node == GraphNode(column: 1, kind: .commit, color: .main, isGhost: true))
    }

    @Test("A repo opened before its refs are read still loads what a pull would bring on the first page")
    func firstPageSeedsRefs() async throws {
        let remotes = try await Self.makeRemotes()
        defer { remotes.remove() }
        try await remotes.serverCommit("server one")
        try await remotes.work.gitAsync("fetch", "-q", "origin")
        try await remotes.work.gitAsync("tag", "v1")
        let vm = RepositoryViewModel(repository: Repository(url: remotes.work.url))
        await vm.history.loadInitial()

        // The first page waits for the branches only; the tags come with loadRefs.
        #expect(vm.refs.contains { $0.isLocalBranch } && vm.refs.contains { $0.isRemoteBranch })
        #expect(!vm.refs.contains { $0.isTag })
        let row = try #require(Self.row("server one", in: vm))
        #expect(vm.history.graphLayouts[row].node.isGhost)
        #expect(!vm.history.isScopeStale)

        let commits = vm.history.commits
        await vm.loadRefs()
        #expect(vm.refs.contains { $0.isTag })
        #expect(vm.history.commits == commits)
        #expect(vm.history.graphLayouts[row].node.isGhost)
        let tagged = try #require(vm.history.commits.first { $0.subject == "c0" })
        #expect(vm.history.refChips.refs(on: tagged.sha).contains { $0.name == "v1" })
    }

    /// Adds `count` tags on HEAD to `repo`'s packed refs. Only `GitCLI.refs()` lists tags, so
    /// reading the refs gets about ten times slower than reading the stashes or the unmerged
    /// branches.
    private static func addTags(_ count: Int, to repo: GitTestRepo) async throws {
        let sha = try await repo.gitAsync("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
        // Zero-padded names sort after the heads and remotes already packed, if any.
        let tags = (1...count).map { String(format: "%@ refs/tags/t%05d\n", sha, $0) }.joined()
        let packed = repo.read(".git/packed-refs") ?? "# pack-refs with: peeled fully-peeled \n"
        try repo.write(packed + tags, to: ".git/packed-refs")
    }

    @Test("A refresh after a fetch from the shell loads what a pull would bring")
    func refreshAfterShellFetch() async throws {
        let remotes = try await Self.makeRemotes()
        defer { remotes.remove() }
        try await Self.addTags(5000, to: remotes.work)
        let vm = RepositoryViewModel(repository: Repository(url: remotes.work.url))
        await vm.loadRefs()
        await vm.history.loadInitial()
        // A fetch the watcher never saw. The refresh reloads the log while it reads the new
        // refs; with the tags, its reload builds its scope before they land, from the old ones.
        try await remotes.serverCommit("server one")
        try await remotes.work.gitAsync("fetch", "-q", "origin")

        await vm.refresh()
        let row = try #require(Self.row("server one", in: vm))
        #expect(vm.history.graphLayouts[row].node.isGhost)
        #expect(!vm.history.isScopeStale)
    }

    @Test("Deleting the local main without reloading the log loads origin/main as the trunk")
    func deleteMainLoadsRemoteTrunk() async throws {
        let remotes = try await Self.makeRemotes()
        defer { remotes.remove() }
        // A local main that tracks nothing, so origin/main isn't in the scope while it exists.
        try await remotes.work.gitAsync("branch", "-q", "--unset-upstream", "main")
        try await remotes.work.gitAsync("switch", "-q", "-c", "feature")
        try await remotes.work.gitAsync("commit", "-q", "--allow-empty", "-m", "feature one")
        try await remotes.serverCommit("server one")
        try await remotes.work.gitAsync("fetch", "-q", "origin")
        let vm = RepositoryViewModel(repository: Repository(url: remotes.work.url))
        await vm.loadRefs()
        await vm.history.loadInitial()
        #expect(Self.row("server one", in: vm) == nil)

        // `deleteBranch` refreshes the refs without reloading the log.
        let main = try #require(vm.localBranches.first { $0.name == "main" })
        _ = try await vm.deleteBranch(main).get()
        let row = try #require(Self.row("server one", in: vm))
        #expect(vm.history.graphLayouts[row].node == GraphNode(column: 1, kind: .commit, color: .main, isGhost: true))
    }

    @Test("Turning the toggle on loads a branch that only exists on the server; turning it off drops it")
    func toggleLoadsServerBranches() async throws {
        let remotes = try await Self.makeRemotes()
        defer { remotes.remove() }
        // `release/2.0` exists on the server only: no local branch tracks it.
        try await remotes.other.gitAsync("switch", "-q", "-c", "release/2.0")
        try await remotes.other.gitAsync("commit", "-q", "--allow-empty", "-m", "release one")
        try await remotes.other.gitAsync("push", "-q", "origin", "release/2.0")
        try await remotes.work.gitAsync("fetch", "-q", "origin")
        let vm = RepositoryViewModel(repository: Repository(url: remotes.work.url))
        // The view model's own store remembers the toggle in the real defaults; this one has
        // its own, and reads the refs from the view model like it does.
        let suite = TestDefaults()
        defer { suite.remove() }
        let history = HistoryStore(cli: GitCLI(workingDirectory: remotes.work.url), tasks: OwnedTasks(),
                                   repositoryURL: remotes.work.url, defaults: suite.defaults)
        history.refsSource = vm
        await vm.loadRefs()
        await history.loadInitial()
        #expect(!history.showsRemoteBranches)
        #expect(!history.commits.contains { $0.subject == "release one" })

        await history.setShowsRemoteBranches(true)
        let row = try #require(history.commits.firstIndex { $0.subject == "release one" })
        #expect(history.graphLayouts[row].node.isGhost)
        #expect(history.loadedScope?.remoteTips.keys.sorted() == ["origin/main", "origin/release/2.0"])
        #expect(!history.isScopeStale)

        await history.setShowsRemoteBranches(false)
        #expect(!history.commits.contains { $0.subject == "release one" })
        #expect(history.loadedScope?.remoteTips.isEmpty == true)
        #expect(!history.isScopeStale)
    }

    @Test("A page fetched after the remote moved still walks the log the first page walked")
    func pagesKeepTheirScope() async throws {
        let remotes = try await Self.makeRemotes(commits: 4)
        defer { remotes.remove() }
        // main is one behind origin/main, so the first page walks from its tip:
        // server one, c3 … c0, 5 commits.
        try await remotes.serverCommit("server one")
        try await remotes.work.gitAsync("fetch", "-q", "origin")
        let vm = RepositoryViewModel(repository: Repository(url: remotes.work.url))
        vm.history.pageSize = { 3 }
        await vm.loadRefs()
        await vm.history.loadInitial()
        let oldWalk = ["server one"] + (0..<4).reversed().map { "c\($0)" }
        #expect(vm.history.commits.map(\.subject) == Array(oldWalk.prefix(3)))
        #expect(vm.history.hasMore)

        // The server rewinds main and work fetches it: origin/main leaves the scope, and a walk
        // from the refs as they are now would have one commit fewer above the page boundary.
        // The refs are read, but nothing reloads the log.
        try await remotes.other.gitAsync("push", "-q", "-f", "origin", "HEAD~1:main")
        try await remotes.work.gitAsync("fetch", "-q", "origin")
        await vm.loadRefs()
        #expect(vm.history.isScopeStale)

        let last = try #require(vm.history.commits.last)
        await vm.history.loadMoreIfNeeded(currentItem: last)
        // The new page starts with c1, the commit after the first page in the old walk.
        #expect(vm.history.commits.map(\.subject) == oldWalk)
        #expect(vm.history.loadedRawCount == 5)
        #expect(vm.history.graphLayouts.count == oldWalk.count)
    }

    // MARK: Scope reloads keep the depth

    /// `work` with c0 … c9 one behind origin/main, three pages of three loaded (server one,
    /// c9 … c2) and `c3`, on the third page, selected.
    private static func threePagesLoaded() async throws -> (remotes: Remotes, vm: RepositoryViewModel, picked: Commit) {
        let remotes = try await makeRemotes(commits: 10)
        try await remotes.serverCommit("server one")
        try await remotes.work.gitAsync("fetch", "-q", "origin")
        let vm = RepositoryViewModel(repository: Repository(url: remotes.work.url))
        vm.history.pageSize = { 3 }
        await vm.loadRefs()
        await vm.history.loadInitial()
        for _ in 0..<2 {
            let last = try #require(vm.history.commits.last)
            await vm.history.loadMoreIfNeeded(currentItem: last)
        }
        #expect(vm.history.loadedRawCount == 9 && vm.history.graphPageEnds == [3, 6, 9])
        let picked = try #require(vm.history.commits.first { $0.subject == "c3" })
        vm.history.selectedCommitId = picked.id
        return (remotes, vm, picked)
    }

    /// The reloaded log is the one the user had after scrolling as far: same raw depth, still
    /// more to load, the selection kept.
    private static func expectDepthKept(_ vm: RepositoryViewModel, picked: Commit,
                                        sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(vm.history.commits.first?.subject == "server two", sourceLocation: sourceLocation)
        #expect(vm.history.loadedRawCount == 9, sourceLocation: sourceLocation)
        #expect(vm.history.graphPageEnds == [3, 6, 9], sourceLocation: sourceLocation)
        #expect(vm.history.hasMore, sourceLocation: sourceLocation)
        #expect(vm.history.selectedCommitId == picked.id, sourceLocation: sourceLocation)
        #expect(!vm.history.isScopeStale, sourceLocation: sourceLocation)
    }

    @Test("The reload after a fetch moved a remote branch keeps the pages loaded, laid out as if scrolled one by one")
    func scopeReloadKeepsDepth() async throws {
        let (remotes, vm, picked) = try await Self.threePagesLoaded()
        defer { remotes.remove() }

        try await remotes.serverCommit("server two")
        #expect(await vm.fetch())
        Self.expectDepthKept(vm, picked: picked)

        // A log scrolled page by page over the same walk has the same rows, pages and graph.
        let scrolled = RepositoryViewModel(repository: Repository(url: remotes.work.url))
        await scrolled.loadRefs()
        let revisions = try #require(vm.history.loadedScope?.revisions)
        #expect(scrolled.history.graphScope() == revisions)
        let cli = remotes.work.cli
        scrolled.history.replaceLog(with: try await cli.log(limit: 3, skip: 0, refs: revisions))
        scrolled.history.appendPage(try await cli.log(limit: 3, skip: 3, refs: revisions))
        scrolled.history.appendPage(try await cli.log(limit: 3, skip: 6, refs: revisions))
        #expect(vm.history.commits == scrolled.history.commits)
        #expect(vm.history.graphPageEnds == scrolled.history.graphPageEnds)
        #expect(vm.history.loadedRawCount == scrolled.history.loadedRawCount)
        #expect(vm.history.graphLayouts == scrolled.history.graphLayouts)
    }

    @Test("A watcher refresh after a fetch from the shell keeps the pages loaded")
    func watcherScopeReloadKeepsDepth() async throws {
        let (remotes, vm, picked) = try await Self.threePagesLoaded()
        defer { remotes.remove() }

        try await remotes.serverCommit("server two")
        try await remotes.work.gitAsync("fetch", "-q", "origin")
        await vm.refreshFromExternalChange()
        Self.expectDepthKept(vm, picked: picked)
    }

    @Test("A reload because a local branch moved starts over from the first page")
    func localReloadStartsOver() async throws {
        let (remotes, vm, _) = try await Self.threePagesLoaded()
        defer { remotes.remove() }

        try await remotes.work.gitAsync("commit", "-q", "--allow-empty", "-m", "local one")
        await vm.refreshFromExternalChange()
        #expect(vm.history.commits.contains { $0.subject == "local one" })
        #expect(vm.history.loadedRawCount == 3 && vm.history.graphPageEnds == [3])
    }
}
