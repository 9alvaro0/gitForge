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
        let vm = RepositoryViewModel(repository: Repository(url: remotes.work.url))
        await vm.history.loadInitial()

        #expect(!vm.refs.isEmpty)
        let row = try #require(Self.row("server one", in: vm))
        #expect(vm.history.graphLayouts[row].node.isGhost)
        #expect(!vm.history.isScopeStale)
    }

    private static let pageSizeKey = "appTheme.commitPageSize"

    @Test("A page fetched after the remote moved still walks the log the first page walked")
    func pagesKeepTheirScope() async throws {
        let previous = UserDefaults.standard.object(forKey: Self.pageSizeKey)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: Self.pageSizeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.pageSizeKey)
            }
        }
        // The smallest page `GitPreferences.commitPageSize` allows.
        UserDefaults.standard.set(50, forKey: Self.pageSizeKey)
        let remotes = try await Self.makeRemotes(commits: 52)
        defer { remotes.remove() }
        // main is one behind origin/main, so the first page walks from its tip:
        // server one, c51 … c0, 53 commits.
        try await remotes.serverCommit("server one")
        try await remotes.work.gitAsync("fetch", "-q", "origin")
        let vm = RepositoryViewModel(repository: Repository(url: remotes.work.url))
        await vm.loadRefs()
        await vm.history.loadInitial()
        let oldWalk = ["server one"] + (0..<52).reversed().map { "c\($0)" }
        #expect(vm.history.commits.map(\.subject) == Array(oldWalk.prefix(50)))
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
        // The new page starts with c2, the commit after the first page in the old walk.
        #expect(vm.history.commits.map(\.subject) == oldWalk)
        #expect(vm.history.loadedRawCount == 53)
        #expect(vm.history.graphLayouts.count == oldWalk.count)
    }
}
