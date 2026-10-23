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

    @Test("Open in repository makes the clone active, goes to its Pull requests and asks for the pull request there")
    func openInRepository() async throws {
        let app = AppState.isolated()
        let repo = try GitTestRepo()
        defer { repo.remove() }
        try repo.commit("first", files: ["a.txt": "a\n"])
        app.ui.workspaceSection = .reviews

        await app.openPullRequest(number: 482, state: .open, inRepositoryAt: repo.url)
        defer { app.catalog.close() }

        #expect(app.catalog.activeRepository?.url.resolvingSymlinksInPath().path
                == repo.url.resolvingSymlinksInPath().path)
        #expect(app.ui.workspaceSection == .pulls)
        // Its list hasn't loaded: the pull request opens once it does.
        #expect(app.catalog.activeViewModel?.pullRequests.pendingSelectionNumber == 482)
        #expect(app.ui.presentedError == nil)
    }

    @Test("Open in repository brings an open repository's list back to Open and opens the pull request there",
          arguments: [PullListScope.mine, .closed])
    func openInRepositoryResetsScope(scope: PullListScope) async throws {
        let app = AppState.isolated()
        let repo = try GitTestRepo()
        defer { repo.remove() }
        try repo.commit("first", files: ["a.txt": "a\n"])
        try await app.openRepository(at: repo.url)
        defer { app.catalog.close() }
        let pulls = try #require(app.catalog.activeViewModel?.pullRequests)
        func pull(_ number: Int, by author: String) -> PullRequest {
            PullRequest(id: "\(number)", number: number, title: "MR \(number)", state: .open, authorLogin: author,
                        authorAvatarURL: nil, sourceBranch: "f/\(number)", targetBranch: "main", webURL: nil,
                        createdAt: nil, updatedAt: nil)
        }
        // The user left this repository's list on Mine (or Closed), on their own pull request.
        pulls.items = [pull(470, by: "marta"), pull(482, by: "lucia")]
        pulls.currentUser = "marta"
        pulls.scope = scope
        pulls.selected = pulls.items[0]
        app.ui.workspaceSection = .reviews

        await app.openPullRequest(number: 482, state: .open, inRepositoryAt: repo.url)

        #expect(app.catalog.activeViewModel?.pullRequests === pulls)
        #expect(app.ui.workspaceSection == .pulls)
        #expect(pulls.scope == .open)
        #expect(pulls.selected?.number == 482)
        #expect(pulls.pendingSelectionNumber == nil)
    }

    @Test("Open in repository of a merged or closed pull request goes to Closed and opens it there",
          arguments: [PullRequest.State.merged, .closed])
    func openClosedInRepository(state: PullRequest.State) async throws {
        let app = AppState.isolated()
        let repo = try GitTestRepo()
        defer { repo.remove() }
        try repo.commit("first", files: ["a.txt": "a\n"])
        try await app.openRepository(at: repo.url)
        defer { app.catalog.close() }
        let pulls = try #require(app.catalog.activeViewModel?.pullRequests)
        // An Other of the inbox (R2 Ruling 9): its list on Open, the pull request among the closed ones.
        pulls.items = [PullRequest(id: "470", number: 470, title: "MR 470", state: .open, authorLogin: "lucia",
                                   authorAvatarURL: nil, sourceBranch: "f/470", targetBranch: "main", webURL: nil,
                                   createdAt: nil, updatedAt: nil)]
        pulls.closedItems = [PullRequest(id: "466", number: 466, title: "MR 466", state: state, authorLogin: "marta",
                                         authorAvatarURL: nil, sourceBranch: "f/466", targetBranch: "main",
                                         webURL: nil, createdAt: nil, updatedAt: nil)]
        pulls.closedLoaded = true
        #expect(pulls.scope == .open)
        app.ui.workspaceSection = .reviews

        await app.openPullRequest(number: 466, state: state, inRepositoryAt: repo.url)

        #expect(app.ui.workspaceSection == .pulls)
        #expect(pulls.scope == .closed)
        #expect(pulls.selected?.number == 466)
        #expect(pulls.pendingSelectionNumber == nil)
    }

    @Test("A clone that can't be opened says why and stays in Reviews")
    func openInMissingRepository() async {
        let app = AppState.isolated()
        app.ui.workspaceSection = .reviews

        await app.openPullRequest(number: 1, state: .open, inRepositoryAt: URL(fileURLWithPath: "/nonexistent/gitforge-tests/ledger"))

        #expect(app.ui.workspaceSection == .reviews)
        #expect(app.ui.presentedError != nil)
        #expect(app.catalog.activeRepository == nil)
    }

    // MARK: Section

    @Test("Reviews is a global section, not one of the repository's workspace items")
    func section() {
        #expect(!WorkspaceSection.workspaceItems.contains(.reviews))
        #expect(WorkspaceSection.reviews.symbol == "tray.2")
    }
}
