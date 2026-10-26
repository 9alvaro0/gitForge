import Foundation
import Testing
@testable import gitForge

@Suite("AppState — Reviews wiring", .serialized)
@MainActor
struct AppStateReviewsTests {
    private func clone(origin: String?) async throws -> GitTestRepo {
        try await GitTestRepo.make { repo in
            if let origin { try repo.git("remote", "add", "origin", origin) }
        }
    }

    @discardableResult
    private func addAccount(_ app: AppState, login: String = "tanuki-test", status: HostingAccount.Status = .ok,
                            linkedProfileId: UUID? = nil) throws -> HostingAccount {
        let account = HostingAccount(instanceId: HostingInstance.gitLabDotCom.id, login: login,
                                     method: .personalToken, status: status, linkedProfileId: linkedProfileId)
        try app.accounts.addAccount(account, secret: AccountSecret(accessToken: "test-pat-value"))
        return account
    }

    // MARK: Local remotes

    @Test("A clone whose origin is on a declared instance is a local remote, with the account assigned to it")
    func localRemote() async throws {
        let app = AppState.isolated()
        let repo = try await clone(origin: "https://gitlab.com/team/app.git")
        defer { repo.remove() }
        let account = try addAccount(app)
        app.catalog.repositories = [Repository(url: repo.url)]
        app.accounts.assign(account.id, repoPath: repo.url.path(percentEncoded: false), remoteName: "origin")

        let remotes = await app.localRemotesForReviews()

        #expect(remotes.count == 1)
        let remote = try #require(remotes.first)
        #expect(remote.host.provider == .gitlab)
        #expect(remote.host.host == "gitlab.com")
        #expect(remote.host.owner == "team")
        #expect(remote.host.repo == "app")
        #expect(remote.repository.url == repo.url)
        #expect(remote.assignedAccountId == account.id)
    }

    @Test("With no account on its instance the remote still counts, with no account")
    func unassigned() async throws {
        let app = AppState.isolated()
        let repo = try await clone(origin: "git@gitlab.com:team/app.git")
        defer { repo.remove() }
        app.catalog.repositories = [Repository(url: repo.url)]

        let remote = try #require(await app.localRemotesForReviews().first)

        #expect(remote.host.id == "gitlab.com/team/app")
        #expect(remote.assignedAccountId == nil)
    }

    @Test("Without an assignment, a clone takes its identity profile's account, as its Pull requests screen does")
    func profileAccount() async throws {
        let app = AppState.isolated()
        let repo = try await GitTestRepo.make { repo in
            try repo.git("remote", "add", "origin", "https://gitlab.com/team/app.git")
            try repo.git("config", "user.email", "lucia@work.example.test")
        }
        defer { repo.remove() }
        let profile = GitProfile(name: "Work", userName: "Lucia", userEmail: "lucia@work.example.test")
        app.profiles.add(profile)
        // First in the store's order, and the owner is neither login.
        try addAccount(app, login: "tanuki-test")
        let linked = try addAccount(app, login: "lucia-work", linkedProfileId: profile.id)
        app.catalog.repositories = [Repository(url: repo.url)]

        let remote = try #require(await app.localRemotesForReviews().first)

        #expect(remote.assignedAccountId == linked.id)
    }

    @Test("A clone set to the system's credentials takes the automatic account, as its Pull requests screen does")
    func systemChoice() async throws {
        let app = AppState.isolated()
        let repo = try await clone(origin: "https://gitlab.com/team/app.git")
        defer { repo.remove() }
        let account = try addAccount(app)
        app.catalog.repositories = [Repository(url: repo.url)]
        app.accounts.setChoice(.system, repoPath: repo.url.path(percentEncoded: false), remoteName: "origin")

        let remote = try #require(await app.localRemotesForReviews().first)

        #expect(remote.assignedAccountId == account.id)
        #expect(app.accounts.choice(repoPath: repo.url.path(percentEncoded: false), remoteName: "origin") == .system)
    }

    @Test("Two accounts and nothing to tell them apart: no account, and nobody is asked")
    func ambiguousClone() async throws {
        let app = AppState.isolated()
        let repo = try await clone(origin: "https://gitlab.com/team/app.git")
        defer { repo.remove() }
        try addAccount(app, login: "tanuki-test")
        try addAccount(app, login: "lucia-work")
        app.catalog.repositories = [Repository(url: repo.url)]

        let remote = try #require(await app.localRemotesForReviews().first)

        #expect(remote.assignedAccountId == nil)
        #expect(app.accountChooser.request == nil)
        #expect(app.accounts.choice(repoPath: repo.url.path(percentEncoded: false), remoteName: "origin") == nil)
    }

    @Test("A clone waits for the account to reconnect it's assigned to, not for one that signs or isn't verified")
    func waitingAccount() async throws {
        let app = AppState.isolated()
        let expiredClone = try await clone(origin: "https://gitlab.com/team/app.git")
        let signingClone = try await clone(origin: "https://gitlab.com/team/api.git")
        let unverifiedClone = try await clone(origin: "https://gitlab.com/team/web.git")
        defer { [expiredClone, signingClone, unverifiedClone].forEach { $0.remove() } }
        let signing = try addAccount(app, login: "tanuki-test")
        let expired = try addAccount(app, login: "ana", status: .needsAttention(.expired))
        let unverified = try addAccount(app, login: "marta", status: .unverified)
        app.catalog.repositories = [expiredClone, signingClone, unverifiedClone].map { Repository(url: $0.url) }
        for (repo, account) in [(expiredClone, expired), (signingClone, signing), (unverifiedClone, unverified)] {
            app.accounts.assign(account.id, repoPath: repo.url.path(percentEncoded: false), remoteName: "origin")
        }

        let remotes = await app.localRemotesForReviews()

        #expect(remotes.map(\.host.repo) == ["app", "api", "web"])
        // The screen's own account is still the one that signs: the assignment can't be used for now.
        #expect(remotes.map(\.assignedAccountId) == [signing.id, signing.id, signing.id])
        #expect(remotes.map(\.waitingAccountId) == [expired.id, nil, nil])
    }

    @Test("A clone without an origin gives nothing")
    func noOrigin() async throws {
        let app = AppState.isolated()
        let repo = try await clone(origin: nil)
        defer { repo.remove() }
        app.catalog.repositories = [Repository(url: repo.url)]

        #expect(await app.localRemotesForReviews().isEmpty)
    }

    @Test("An origin on an undeclared host gives nothing")
    func undeclaredHost() async throws {
        let app = AppState.isolated()
        let repo = try await clone(origin: "https://git.example.test/team/app.git")
        defer { repo.remove() }
        app.catalog.repositories = [Repository(url: repo.url)]

        #expect(await app.localRemotesForReviews().isEmpty)
    }

    @Test("Remotes come back in the catalog's order, skipping the clones that give none")
    func catalogOrder() async throws {
        let app = AppState.isolated()
        let first = try await clone(origin: "https://gitlab.com/team/first.git")
        let bare = try await clone(origin: nil)
        let second = try await clone(origin: "https://github.com/octo/second.git")
        let third = try await clone(origin: "https://gitlab.com/team/third.git")
        defer { [first, bare, second, third].forEach { $0.remove() } }
        app.catalog.repositories = [first, bare, second, third].map { Repository(url: $0.url) }

        let remotes = await app.localRemotesForReviews()

        #expect(remotes.map(\.host.id) == ["gitlab.com/team/first", "github.com/octo/second", "gitlab.com/team/third"])
        #expect(remotes.map(\.repository.url) == [first.url, second.url, third.url])
    }

    @Test("A catalog longer than the reads in flight loses none and keeps its order")
    func longCatalog() async throws {
        let app = AppState.isolated()
        var repos: [GitTestRepo] = []
        defer { repos.forEach { $0.remove() } }
        for index in 0..<20 {
            // Every third clone has no origin.
            repos.append(try await clone(origin: index % 3 == 0 ? nil : "https://gitlab.com/team/app\(index).git"))
        }
        app.catalog.repositories = repos.map { Repository(url: $0.url) }

        let remotes = await app.localRemotesForReviews()

        let expected = (0..<20).filter { $0 % 3 != 0 }
        #expect(remotes.map(\.host.repo) == expected.map { "app\($0)" })
        #expect(remotes.map(\.repository.url) == expected.map { repos[$0].url })
    }

    @Test("An empty catalog gives nothing")
    func emptyCatalog() async {
        #expect(await AppState.isolated().localRemotesForReviews().isEmpty)
    }

    // MARK: Accounts

    @Test("The inbox has no accounts until one is connected")
    func noAccounts() {
        #expect(!AppState.isolated().reviews.hasAccounts)
    }

    @Test("Accounts that sign, and those to reconnect, are the inbox's; an unverified one is not",
          arguments: [
              (HostingAccount.Status.ok, true),
              (.expiringSoon, true),
              (.needsAttention(.expired), true),
              (.needsAttention(.missingScopes), true),
              (.unverified, false),
          ])
    func accountsByStatus(status: HostingAccount.Status, counts: Bool) throws {
        let app = AppState.isolated()
        _ = try addAccount(app, status: status)

        #expect(app.reviews.hasAccounts == counts)
    }

    @Test("The inbox's environment doesn't keep the app state alive")
    func noRetainCycle() async {
        weak var weakApp: AppState?
        do {
            let app = AppState.isolated()
            weakApp = app
            _ = await app.localRemotesForReviews()
            _ = app.reviews.hasAccounts
        }
        #expect(weakApp == nil)
    }

    // MARK: Snapshot

    private static func snapshotRepo() -> ReviewRepo {
        let instance = HostingInstance(kind: .gitlab, host: "gitlab.example.test")
        return ReviewRepo(host: RemoteHost.make(fullName: "apps/payments/backend/ledger", on: instance)!,
                          accountId: UUID(), sources: [], lastActivity: nil,
                          cloneURL: "https://gitlab.example.test/apps/payments/backend/ledger.git", localURL: nil)
    }

    @Test("The inbox loads from the snapshot store the app state was given")
    func givenSnapshots() {
        let store = ReviewsSnapshotStore(directory: TemporaryDirectories.make("gitForge-snapshot"))
        let repo = Self.snapshotRepo()
        store.save(ReviewsSnapshot(version: ReviewsSnapshot.currentVersion, savedAt: Date(timeIntervalSince1970: 1_790_000_000),
                                   repos: [repo], pulls: [:], memberships: [:], logins: [:]))
        let app = AppState.isolated(reviewsSnapshots: store)

        app.reviews.loadSnapshot()

        #expect(app.reviews.repos.map(\.id) == [repo.id])
    }

    // MARK: Open in repository

    private static let instance = HostingInstance(kind: .gitlab, host: "gitlab.example.test")

    private static func teamApp(cloneAt url: URL?) throws -> ReviewRepo {
        ReviewRepo(host: try #require(RemoteHost.make(fullName: "team/app", on: instance)),
                   accountId: UUID(), sources: [], lastActivity: nil,
                   cloneURL: "https://gitlab.example.test/team/app.git", localURL: url)
    }

    private static func pull(_ number: Int, by author: String, state: PullRequest.State = .open) -> PullRequest {
        PullRequest(id: "iid:\(number)", number: number, title: "MR \(number)", state: state, authorLogin: author,
                    authorAvatarURL: nil, sourceBranch: "f/\(number)", targetBranch: "main", webURL: nil,
                    createdAt: nil, updatedAt: nil)
    }

    private static func save(_ repo: ReviewRepo, pulls: [PullRequest], in store: ReviewsSnapshotStore) {
        store.save(ReviewsSnapshot(version: ReviewsSnapshot.currentVersion,
                                   savedAt: Date(timeIntervalSince1970: 1_790_000_000),
                                   repos: [repo], pulls: [repo.id: pulls], memberships: [:],
                                   logins: [repo.accountId: "marta"]))
    }

    /// An app whose inbox follows `repo` with `pulls` read, marta being the user.
    private static func appFollowing(_ repo: ReviewRepo, pulls: [PullRequest]) -> AppState {
        let store = ReviewsSnapshotStore(directory: TemporaryDirectories.make("gitForge-app-reviews"))
        save(repo, pulls: pulls, in: store)
        let app = AppState.isolated(reviewsSnapshots: store)
        app.reviews.loadSnapshot()
        return app
    }

    @Test("Open in repository makes the clone active, goes to Pull requests and shows the pull request where the inbox has it",
          arguments: [("marta", PullsTab.mine), ("lucia", PullsTab.team)])
    func openInRepository(author: String, half: PullsTab) async throws {
        let clone = try GitTestRepo()
        defer { clone.remove() }
        try clone.commit("first", files: ["a.txt": "a\n"])
        let repo = try Self.teamApp(cloneAt: clone.url)
        let app = Self.appFollowing(repo, pulls: [Self.pull(482, by: author)])
        let item = try #require(app.reviews.inboxRows.first)
        // The section was left on the repository's Closed list, on another half.
        app.reviews.tab = .closed
        app.ui.workspaceSection = .history

        await app.openPullRequest(item, inRepositoryAt: clone.url)
        defer { app.catalog.close() }

        #expect(app.catalog.activeRepository?.url.resolvingSymlinksInPath().path
                == clone.url.resolvingSymlinksInPath().path)
        #expect(app.ui.workspaceSection == .pulls)
        #expect(app.reviews.selectedID == item.id)
        #expect(app.reviews.tab == half)
        #expect(app.ui.presentedError == nil)
        // The inbox had it: the repository's own list is left alone.
        #expect(app.catalog.activeViewModel?.pullRequests.pendingSelectionNumber == nil)
    }

    @Test("A pull request the inbox no longer has opens in the repository's own list: Closed for a merged or closed one, else Open",
          arguments: [(PullRequest.State.open, PullsTab.open), (.draft, .open), (.merged, .closed), (.closed, .closed)])
    func openInRepositoryFallsBack(state: PullRequest.State, tab: PullsTab) async throws {
        let clone = try GitTestRepo()
        defer { clone.remove() }
        try clone.commit("first", files: ["a.txt": "a\n"])
        let app = AppState.isolated()
        // A row from a list that has since changed: no longer among the inbox's.
        let item = InboxPull(repo: try Self.teamApp(cloneAt: clone.url), pull: Self.pull(482, by: "lucia", state: state))
        app.ui.workspaceSection = .history

        await app.openPullRequest(item, inRepositoryAt: clone.url)
        defer { app.catalog.close() }

        #expect(app.ui.workspaceSection == .pulls)
        #expect(app.reviews.tab == tab)
        // Its list hasn't loaded: the pull request opens once it does.
        #expect(app.catalog.activeViewModel?.pullRequests.pendingSelectionNumber == 482)
        #expect(app.reviews.selectedID == nil)
    }

    @Test("A pull request the inbox no longer has opens at once when the repository's list already shows it")
    func openInRepositoryFallsBackToLoadedList() async throws {
        let clone = try GitTestRepo()
        defer { clone.remove() }
        try clone.commit("first", files: ["a.txt": "a\n"])
        let app = AppState.isolated()
        try await app.openRepository(at: clone.url)
        defer { app.catalog.close() }
        let pulls = try #require(app.catalog.activeViewModel?.pullRequests)
        pulls.items = [Self.pull(470, by: "marta"), Self.pull(482, by: "lucia")]
        pulls.selected = pulls.items[0]
        let item = InboxPull(repo: try Self.teamApp(cloneAt: clone.url), pull: Self.pull(482, by: "lucia"))

        await app.openPullRequest(item, inRepositoryAt: clone.url)

        #expect(app.reviews.tab == .open)
        #expect(pulls.selected?.number == 482)
        #expect(pulls.pendingSelectionNumber == nil)
    }

    @Test("A clone that can't be opened says why and leaves the section where it was")
    func openInMissingRepository() async throws {
        let app = AppState.isolated()
        app.ui.workspaceSection = .pulls
        app.reviews.tab = .mine
        let missing = URL(fileURLWithPath: "/nonexistent/gitforge-tests/ledger")
        let item = InboxPull(repo: try Self.teamApp(cloneAt: missing), pull: Self.pull(1, by: "lucia"))

        await app.openPullRequest(item, inRepositoryAt: missing)

        #expect(app.ui.workspaceSection == .pulls)
        #expect(app.reviews.tab == .mine)
        #expect(app.ui.presentedError != nil)
        #expect(app.catalog.activeRepository == nil)
    }

    // MARK: The open repository

    /// Counts the changes `withObservationTracking` reports.
    private final class ChangeCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var value: Int { lock.withLock { count } }
        func bump() { lock.withLock { count += 1 } }
    }

    @Test("The inbox reads the open repository from the catalog: its folder and its own pull requests store")
    func activeRepositoryIsTheCatalogs() async throws {
        let clone = try GitTestRepo()
        defer { clone.remove() }
        try clone.commit("first", files: ["a.txt": "a\n"])
        let store = ReviewsSnapshotStore(directory: TemporaryDirectories.make("gitForge-app-active"))
        let app = AppState.isolated(reviewsSnapshots: store)
        #expect(app.reviews.activeRepository == nil)
        #expect(app.reviews.activeRepoKey == nil)

        try await app.openRepository(at: clone.url)
        defer { app.catalog.close() }
        let viewModel = try #require(app.catalog.activeViewModel)

        let active = try #require(app.reviews.activeRepository)
        #expect(active.localURL == viewModel.repository.url)
        // The same instance the section's view is given (`ContentRouter`).
        #expect(active.store === viewModel.pullRequests)

        // Followed by its clone, it is the open repository and its store opens its detail.
        let repo = try Self.teamApp(cloneAt: viewModel.repository.url)
        Self.save(repo, pulls: [Self.pull(482, by: "lucia")], in: store)
        app.reviews.loadSnapshot()
        #expect(app.reviews.activeRepoKey == repo.id)
        #expect(app.reviews.detailStore(for: repo.id) === viewModel.pullRequests)

        app.catalog.close()
        #expect(app.reviews.activeRepository == nil)
    }

    @Test("Opening another repository changes what the inbox reads, so the views watching it redraw")
    func activeRepositoryIsObserved() async throws {
        let first = try GitTestRepo()
        let second = try GitTestRepo()
        defer { first.remove(); second.remove() }
        try first.commit("first", files: ["a.txt": "a\n"])
        try second.commit("first", files: ["b.txt": "b\n"])
        let app = AppState.isolated()
        try await app.openRepository(at: first.url)
        defer { app.catalog.close() }
        let before = app.reviews.activeRepository?.store

        let changes = ChangeCounter()
        withObservationTracking { _ = app.reviews.activeRepository?.localURL } onChange: { changes.bump() }
        try await app.openRepository(at: second.url)

        #expect(changes.value == 1)
        #expect(app.reviews.activeRepository?.store !== before)
        #expect(app.reviews.activeRepository?.store === app.catalog.activeViewModel?.pullRequests)
    }

    // MARK: The tab

    @Test("The tab the section was left on comes back with the next launch")
    func tabPersists() {
        let defaults = TestDefaults(prefix: "gitForge-app-tab").defaults
        let first = AppState.isolated(defaults: defaults)
        #expect(first.reviews.tab == .team)

        first.reviews.tab = .closed

        #expect(AppState.isolated(defaults: defaults).reviews.tab == .closed)
        first.reviews.tab = .mine
        #expect(AppState.isolated(defaults: defaults).reviews.tab == .mine)
    }

    @Test("A saved tab that doesn't exist or can't be read starts on Team", arguments: ["reviews", "", "x", "Team"])
    func unreadableTab(saved: String) {
        let defaults = TestDefaults(prefix: "gitForge-app-tab").defaults
        defaults.set(saved, forKey: "pulls.lastTab")

        #expect(AppState.isolated(defaults: defaults).reviews.tab == .team)
    }

    @Test("A stored value that isn't text starts on Team")
    func tabOfAnotherType() {
        let defaults = TestDefaults(prefix: "gitForge-app-tab").defaults
        defaults.set(3, forKey: "pulls.lastTab")

        #expect(AppState.isolated(defaults: defaults).reviews.tab == .team)
    }
}
