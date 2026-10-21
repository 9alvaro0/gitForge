import Foundation
import Testing
@testable import gitForge

@Suite("Review threads — parsing")
struct ReviewThreadParsingTests {
    static let github = RemoteHost(provider: .github, host: "github.com", owner: "octo", repo: "app")

    @Test("GitHub threads parse sides, outdated and reply targets")
    func gitHubThreads() throws {
        let page = try GitHubPullRequestProvider.parseThreads(Fixture.data("github-review-threads"))
        #expect(page.threads.map(\.ref) == [DiffLineRef(side: .new, line: 12), DiffLineRef(side: .old, line: 11), nil])
        #expect(page.threads[0].comments.count == 2)
        #expect(page.threads[0].comments[0].authorLogin == "marta")
        #expect(page.threads[0].comments[0].body == "Should this retry forever?")
        #expect(page.threads[0].replyToCommentId == "1001")
        #expect(page.threads[0].canResolve && !page.threads[0].canUnresolve && page.threads[0].canReply)
        #expect(page.threads[1].isResolved && page.threads[1].resolvedBy == "marta")
        #expect(page.threads[1].canUnresolve && !page.threads[1].canResolve)
        #expect(page.threads[2].isOutdated && page.threads[2].originalLine == 9)
        #expect(page.threads[2].comments[0].authorLogin == nil)
        #expect(page.nextCursor == "Y3Vyc29y")
    }

    @Test("GraphQL endpoint for github.com and Enterprise")
    func gitHubGraphQLEndpoint() {
        #expect(GitHubPullRequestProvider.graphQLEndpoint(for: Self.github).absoluteString == "https://api.github.com/graphql")
        let enterprise = RemoteHost(provider: .github, host: "ghe.example.test", owner: "octo", repo: "app",
                                    apiBaseURL: URL(string: "https://ghe.example.test/api/v3"))
        #expect(GitHubPullRequestProvider.graphQLEndpoint(for: enterprise).absoluteString == "https://ghe.example.test/api/graphql")
        let bare = RemoteHost(provider: .github, host: "ghe.example.test", owner: "octo", repo: "app")
        #expect(GitHubPullRequestProvider.graphQLEndpoint(for: bare).absoluteString == "https://ghe.example.test/api/graphql")
    }

    @Test("collectPages stops at the first short page and at the cap")
    func collectPages() async throws {
        let pages = PageLog()
        let short = try await RemoteAPI.collectPages(pageSize: 100, maxPages: 30) { page in
            await pages.append(page)
            return Array(repeating: page, count: page < 3 ? 100 : 7)
        }
        #expect(short.count == 207)
        #expect(await pages.all == [1, 2, 3])

        let capped = PageLog()
        let full = try await RemoteAPI.collectPages(pageSize: 100, maxPages: 30) { page in
            await capped.append(page)
            return Array(repeating: page, count: 100)
        }
        #expect(full.count == 3000)
        #expect(await capped.all.count == 30)
    }
}

private actor PageLog {
    private(set) var all: [Int] = []
    func append(_ page: Int) { all.append(page) }
}

/// GitHub's file list and threads against a stub server: both page.
@Suite("Review threads — GitHub paging")
@MainActor
struct GitHubThreadPagingTests {
    private static func setUp() -> (StubServer, GitHubPullRequestProvider, RemoteHost) {
        let server = StubServer()
        let provider = GitHubPullRequestProvider(session: server.http.session)
        let host = RemoteHost(provider: .github, host: server.host, owner: "octo", repo: "app",
                              apiBaseURL: URL(string: "https://\(server.host)/api/v3"))
        return (server, provider, host)
    }

    private static func files(_ count: Int, from start: Int) -> Data {
        let items = (start..<(start + count)).map {
            #"{"filename":"f\#($0).swift","status":"modified","additions":1,"deletions":0,"patch":"@@ -1 +1 @@\n-a\n+b"}"#
        }
        return Data("[\(items.joined(separator: ","))]".utf8)
    }

    @Test("A PR with more than 100 files reads every page")
    func filesPage() async throws {
        let (server, provider, host) = Self.setUp()
        let path = "/api/v3/repos/octo/app/pulls/7/files"
        server.on("GET", path, body: Self.files(100, from: 0))
        server.on("GET", path, body: Self.files(1, from: 100))
        let files = try await provider.fetchFiles(host: host, number: 7, token: "t")
        #expect(files.count == 101)
        #expect(files.last?.path == "f100.swift")
        #expect(server.requests("GET", path).map { $0.query["page"] } == ["1", "2"])
        #expect(server.requests("GET", path).allSatisfy { $0.query["per_page"] == "100" })
    }

    @Test("Threads follow the cursor until the last page")
    func threadsPage() async throws {
        let (server, provider, host) = Self.setUp()
        server.on("POST", "/api/graphql", fixture: "github-review-threads")
        server.on("POST", "/api/graphql", body: Data(#"""
        {"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},
        "nodes":[{"id":"PRRT_last","isResolved":false,"isOutdated":false,"path":"a.swift","line":1,"originalLine":1,
        "diffSide":"RIGHT","viewerCanResolve":true,"viewerCanUnresolve":false,"viewerCanReply":true,"resolvedBy":null,
        "comments":{"nodes":[]}}]}}}}}
        """#.utf8))
        let pull = PullRequest(id: "7", number: 7, title: "T", state: .open, authorLogin: "marta", authorAvatarURL: nil,
                               sourceBranch: "f", targetBranch: "main", webURL: nil, createdAt: nil, updatedAt: nil,
                               headSha: "abc")
        let threads = try await provider.fetchThreads(host: host, pull: pull, detail: nil, token: "t")
        #expect(threads.map(\.id) == ["PRRT_open", "PRRT_resolved", "PRRT_outdated", "PRRT_last"])
        let afters = server.requests("POST", "/api/graphql").map {
            (($0.json?["variables"] as? [String: Any])?["after"] as? String) ?? "-"
        }
        #expect(afters == ["-", "Y3Vyc29y"])
        let variables = try #require(server.requests.first?.json?["variables"] as? [String: Any])
        #expect(variables["owner"] as? String == "octo" && variables["name"] as? String == "app" && variables["number"] as? Int == 7)
    }
}
