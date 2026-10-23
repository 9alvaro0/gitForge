import Foundation
import Testing
@testable import gitForge

/// What ⌘K lists from the inbox (R2 Rulings 2, 5 and 6): the pull requests,
/// the followed repos that aren't on this Mac and a pasted link's row.
@Suite("Command palette builder")
@MainActor
struct CommandPaletteBuilderTests {
    private static let gitLab = HostingInstance(kind: .gitlab, host: "gitlab.example.test")
    private static let paymentsApp = "apps/payments/android/payments-app"
    private static let ledger = "apps/payments/backend/ledger"

    private static func repo(_ path: String, localURL: URL? = nil) -> ReviewRepo {
        ReviewRepo(host: RemoteHost.make(fullName: path, on: gitLab)!, accountId: UUID(), sources: [],
                   lastActivity: nil, cloneURL: "https://gitlab.example.test/\(path).git", localURL: localURL)
    }

    private static func pull(_ number: Int, title: String = "Retry card authorisation", author: String? = "marta",
                             authorName: String? = "Marta Ruiz", branch: String = "fix/retry") -> PullRequest {
        PullRequest(id: "iid:\(number)", number: number, title: title, state: .open, authorLogin: author,
                    authorAvatarURL: nil, sourceBranch: branch, targetBranch: "main", webURL: nil,
                    createdAt: nil, updatedAt: nil, authorName: authorName)
    }

    private static func build(pulls: [InboxPull] = [], unclonedRepos: [ReviewRepo] = [],
                              repositories: [Repository] = []) -> [CommandPaletteItem] {
        CommandPaletteBuilder.build(repositories: repositories, branches: [], commits: [], workingFiles: [],
                                    pulls: pulls, unclonedRepos: unclonedRepos)
    }

    // MARK: Pull requests

    @Test("A pull request is a row by its title, with its reference and repo, found by number, branch and author")
    func pullItem() throws {
        let inbox = InboxPull(repo: Self.repo(Self.paymentsApp), pull: Self.pull(482))

        let item = try #require(Self.build(pulls: [inbox]).first { $0.kind == .pull })

        #expect(item.label == "Retry card authorisation")
        #expect(item.hint == "!482 · payments-app")
        #expect(item.number == 482)
        #expect(item.keywords == [Self.paymentsApp, "fix/retry", "marta", "Marta Ruiz", "482"])
        #expect(item.action == .openPull(id: inbox.id))
    }

    @Test("A pull request without an author keeps the rest of its keywords")
    func pullItemWithoutAuthor() throws {
        let inbox = InboxPull(repo: Self.repo(Self.paymentsApp), pull: Self.pull(7, author: nil, authorName: nil))

        let item = try #require(Self.build(pulls: [inbox]).first { $0.kind == .pull })

        #expect(item.keywords == [Self.paymentsApp, "fix/retry", "7"])
    }

    @Test("A GitHub pull request is written #7")
    func gitHubReference() throws {
        let host = try #require(RemoteHost.make(fullName: "octo/lib", on: .gitHubDotCom))
        let repo = ReviewRepo(host: host, accountId: UUID(), sources: [], lastActivity: nil,
                              cloneURL: "https://github.com/octo/lib.git", localURL: nil)

        let item = try #require(Self.build(pulls: [InboxPull(repo: repo, pull: Self.pull(7))]).first { $0.kind == .pull })

        #expect(item.hint == "#7 · lib")
    }

    @Test("Only the first 300 pull requests are listed")
    func pullLimit() {
        let repo = Self.repo(Self.paymentsApp)
        let pulls = (1...301).map { InboxPull(repo: repo, pull: Self.pull($0)) }

        let items = Self.build(pulls: pulls).filter { $0.kind == .pull }

        #expect(CommandPaletteBuilder.pullLimit == 300)
        #expect(items.count == 300)
        #expect(items.first?.number == 1)
        #expect(items.last?.number == 300)
    }

    @Test("Without an inbox the palette is what it was")
    func noInbox() {
        let items = Self.build()
        #expect(!items.contains { $0.kind == .pull })
        #expect(!items.contains { $0.kind == .repo })
    }

    // MARK: Repos that aren't cloned

    @Test("A followed repo with no clone comes after the local ones, marked Not cloned")
    func unclonedAfterLocals() {
        let local = Repository(url: URL(fileURLWithPath: "/r/team/app"))
        let uncloned = Self.repo(Self.ledger)

        let repos = Self.build(unclonedRepos: [uncloned], repositories: [local]).filter { $0.kind == .repo }

        #expect(repos.map(\.label) == ["team/app", Self.ledger])
        #expect(repos.map(\.hint) == [nil, "Not cloned"])
        #expect(repos.map(\.action) == [.openRepo(local.url), .showReviews(repoKey: uncloned.id)])
    }

    // MARK: Links

    private static let instances = HostingInstance.builtIns + [gitLab]

    @Test("A pasted link is one row that opens it, with the repo and reference")
    func linkRow() throws {
        let text = "https://gitlab.example.test/\(Self.paymentsApp)/-/merge_requests/482"
        let link = try #require(PullRequestLink.parse(text, instances: Self.instances))

        let rows = CommandPaletteBuilder.linkItems(for: text, instances: Self.instances)

        let row = try #require(rows.first)
        #expect(rows.count == 1)
        #expect(row.kind == .pull)
        #expect(row.label == "Open payments-app !482")
        #expect(row.hint == "apps/payments/android")
        #expect(row.action == .openPullLink(link))
    }

    @Test("A GitHub link says #7")
    func gitHubLinkRow() throws {
        let rows = CommandPaletteBuilder.linkItems(for: "https://github.com/octo/lib/pull/7/files",
                                                   instances: Self.instances)

        #expect(rows.first?.label == "Open lib #7")
        #expect(rows.first?.hint == "octo")
    }

    @Test("A link on a host that isn't declared offers to add it, as the kind its shape says")
    func suggestionRow() throws {
        let rows = CommandPaletteBuilder.linkItems(
            for: "https://code.example.test/apps/payments/android/payments-app/-/merge_requests/482",
            instances: Self.instances)

        let row = try #require(rows.first)
        #expect(rows.count == 1)
        #expect(row.kind == .pull)
        #expect(row.label == "Add as GitLab instance…")
        #expect(row.hint == "code.example.test")
        #expect(row.action == .addInstance(kind: .gitlab, host: "code.example.test"))
    }

    @Test("Any other text gives no row")
    func notALink() {
        #expect(CommandPaletteBuilder.linkItems(for: "retry", instances: Self.instances).isEmpty)
        #expect(CommandPaletteBuilder.linkItems(for: "", instances: Self.instances).isEmpty)
        #expect(CommandPaletteBuilder.linkItems(for: "https://gitlab.example.test/team/app", instances: Self.instances).isEmpty)
    }
}
