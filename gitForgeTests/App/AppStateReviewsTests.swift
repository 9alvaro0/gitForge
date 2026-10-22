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

    private func addAccount(_ app: AppState, status: HostingAccount.Status = .ok) throws -> HostingAccount {
        let account = HostingAccount(instanceId: HostingInstance.gitLabDotCom.id, login: "tanuki-test",
                                     method: .personalToken, status: status)
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

    @Test("Without an assignment the remote still counts, with no account")
    func unassigned() async throws {
        let app = AppState.isolated()
        let repo = try await clone(origin: "git@gitlab.com:team/app.git")
        defer { repo.remove() }
        app.catalog.repositories = [Repository(url: repo.url)]

        let remote = try #require(await app.localRemotesForReviews().first)

        #expect(remote.host.id == "gitlab.com/team/app")
        #expect(remote.assignedAccountId == nil)
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

    // MARK: Section

    @Test("Reviews is a global section, not one of the repository's workspace items")
    func section() {
        #expect(!WorkspaceSection.workspaceItems.contains(.reviews))
        #expect(WorkspaceSection.reviews.symbol == "tray.2")
    }
}
