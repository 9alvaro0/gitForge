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

    // MARK: Search all (R3 Ruling 12)

    private static let enterprise = HostingInstance(kind: .github, host: "ghe.example.test")

    private static func searchItems(_ query: String, instances: [HostingInstance] = [gitLab],
                                    searches: [UUID: HostSearchState] = [:],
                                    followed: Set<String> = []) -> [CommandPaletteItem] {
        CommandPaletteBuilder.searchItems(for: query, instances: instances, searches: searches, followed: followed)
    }

    private static func state(_ query: String, _ phase: HostSearchState.Phase) -> [UUID: HostSearchState] {
        [gitLab.id: HostSearchState(query: query, phase: phase)]
    }

    private static func found(_ path: String) throws -> FoundRepo {
        FoundRepo(host: try #require(RemoteHost.make(fullName: path, on: gitLab)), instanceId: gitLab.id,
                  cloneURL: "https://gitlab.example.test/\(path).git")
    }

    @Test("Under three characters, without the spaces around them, or with no instance, there's no row")
    func searchTooShort() {
        #expect(Self.searchItems("re").isEmpty)
        #expect(Self.searchItems("  re  ").isEmpty)
        #expect(Self.searchItems("retry", instances: []).isEmpty)
    }

    @Test("Each instance gets a row that searches it for the trimmed text, in the order given")
    func searchRows() {
        let rows = Self.searchItems("  retry ", instances: [Self.gitLab, Self.enterprise])

        #expect(rows.map(\.kind) == [.remote, .remote])
        #expect(rows.map(\.label) == ["Search all of gitlab.example.test", "Search all of ghe.example.test"])
        #expect(rows.map(\.hint) == ["“retry”", "“retry”"])
        #expect(rows.map(\.action) == [.searchHost(instanceId: Self.gitLab.id, query: "retry"),
                                       .searchHost(instanceId: Self.enterprise.id, query: "retry")])
        #expect(rows.allSatisfy { !$0.isLoading && $0.symbol == nil })
        #expect(CommandPaletteItem.Kind.remote.symbol == "globe")
    }

    @Test("While the host is searched for that text, its row says so with a spinner and does nothing")
    func searchSearching() {
        let rows = Self.searchItems("retry ", searches: Self.state("retry", .searching))

        #expect(rows.count == 1)
        #expect(rows.first?.label == "Searching gitlab.example.test…")
        #expect(rows.first?.isLoading == true)
        #expect(rows.first?.action == .noop)
    }

    @Test("A search made for other text gives back the row that searches")
    func searchOtherQuery() throws {
        let rows = Self.searchItems("retry", searches: Self.state("other", .found(HostSearchResults(repos: [try Self.found(Self.ledger)]))))

        #expect(rows.map(\.label) == ["Search all of gitlab.example.test"])
        #expect(rows.map(\.action) == [.searchHost(instanceId: Self.gitLab.id, query: "retry")])
    }

    @Test("What was found: its pull requests as ⌘K shows them, then its repos, Followed if followed; each instance in turn")
    func searchFound() throws {
        let link = try #require(PullRequestLink.parse(
            "https://gitlab.example.test/\(Self.paymentsApp)/-/merge_requests/482", instances: [Self.gitLab]))
        let pull = FoundPull(link: link, title: "Retry card authorisation", authorLogin: "marta",
                             updatedAt: nil, isDraft: false)
        let app = try Self.found(Self.paymentsApp)
        let ledger = try Self.found(Self.ledger)
        let results = HostSearchResults(pulls: [pull], repos: [app, ledger])

        let rows = Self.searchItems("retry", instances: [Self.gitLab, Self.enterprise],
                                    searches: Self.state("retry", .found(results)),
                                    followed: [FollowedRepos.key(app.host)])

        #expect(rows.map(\.kind) == [.remote, .remote, .remote, .remote])
        #expect(rows.map(\.label) == ["Retry card authorisation", Self.paymentsApp, Self.ledger,
                                      "Search all of ghe.example.test"])
        #expect(rows.map(\.hint) == ["!482 · payments-app", "Followed", nil, "“retry”"])
        #expect(rows.map(\.action) == [.openPullLink(link), .openFoundRepo(app), .openFoundRepo(ledger),
                                       .searchHost(instanceId: Self.enterprise.id, query: "retry")])
        #expect(rows.map(\.symbol) == [CommandPaletteItem.Kind.pull.symbol, CommandPaletteItem.Kind.repo.symbol,
                                       CommandPaletteItem.Kind.repo.symbol, nil])
        #expect(rows.allSatisfy { !$0.isLoading })
    }

    @Test("At most ten pull requests and ten repos")
    func searchFoundLimit() throws {
        let pulls = try (1...12).map { number in
            FoundPull(link: try #require(PullRequestLink.parse(
                "https://gitlab.example.test/\(Self.paymentsApp)/-/merge_requests/\(number)", instances: [Self.gitLab])),
                      title: "MR \(number)", authorLogin: "ana", updatedAt: nil, isDraft: false)
        }
        let repos = try (1...12).map { try Self.found("oss/lib-\($0)") }

        let rows = Self.searchItems("retry", searches: Self.state("retry", .found(HostSearchResults(pulls: pulls, repos: repos))))

        #expect(rows.count == 20)
        #expect(rows.prefix(10).map(\.label) == (1...10).map { "MR \($0)" })
        #expect(rows.suffix(10).map(\.label) == (1...10).map { "oss/lib-\($0)" })
    }

    @Test("Nothing found says so and does nothing")
    func searchNothing() {
        let rows = Self.searchItems("retry", searches: Self.state("retry", .found(HostSearchResults())))

        #expect(rows.map(\.label) == ["Nothing found on gitlab.example.test"])
        #expect(rows.map(\.action) == [.noop])
    }

    @Test("A failed search says why, and picking it searches again")
    func searchFailed() {
        let rows = Self.searchItems("retry", searches: Self.state("retry", .failed("Server error")))

        #expect(rows.map(\.label) == ["Couldn't search gitlab.example.test"])
        #expect(rows.map(\.hint) == ["Server error"])
        #expect(rows.map(\.action) == [.searchHost(instanceId: Self.gitLab.id, query: "retry")])
    }

    @Test("A host with no account that signs asks to connect one")
    func searchConnect() {
        let rows = Self.searchItems("retry", searches: Self.state("retry", .connectAccount))

        #expect(rows.map(\.label) == ["Connect an account on gitlab.example.test…"])
        #expect(rows.map(\.action) == [.connectAccount(instanceId: Self.gitLab.id)])
    }
}
