import Foundation
import Testing
@testable import gitForge

@Suite("Host search")
@MainActor
struct HostSearchTests {
    // The web URLs in the fixtures live on these hosts; the instances' API
    // bases point at the stub server, which is where the requests go.
    static let gitHubWebHost = "ghe.example.test"
    static let gitLabWebHost = "code.example.test"

    private static func gitHub() -> (server: StubServer, search: GitHubHostSearch, instance: HostingInstance) {
        let server = StubServer()
        let instance = HostingInstance(kind: .github, host: gitHubWebHost,
                                       apiBaseURL: URL(string: "https://\(server.host)/api/v3"))
        return (server, GitHubHostSearch(session: server.http.session), instance)
    }

    private static func gitLab() -> (server: StubServer, search: GitLabHostSearch, instance: HostingInstance) {
        let server = StubServer()
        let instance = HostingInstance(kind: .gitlab, host: gitLabWebHost,
                                       apiBaseURL: URL(string: "https://\(server.host)/api/v4"))
        return (server, GitLabHostSearch(session: server.http.session), instance)
    }

    private static func link(_ fullName: String, _ number: Int, on instance: HostingInstance) throws -> PullRequestLink {
        PullRequestLink(host: try #require(RemoteHost.make(fullName: fullName, on: instance)),
                        number: number, instanceId: instance.id)
    }

    private static func timestamp(_ raw: String) throws -> Date {
        try #require(RemoteAPI.parseTimestamp(raw))
    }

    /// A GitLab merge request list for `group`; `minutes` are the minutes of
    /// 2026-10-20 10:xx (nil = no `updated_at`), one merge request each, numbered from `firstNumber`.
    private static func mergeRequests(group: String, firstNumber: Int, minutes: [Int?]) -> Data {
        let items = minutes.enumerated().map { offset, minute -> String in
            let number = firstNumber + offset
            let updated = minute.map { #""2026-10-20T10:\#(String(format: "%02d", $0)):00Z""# } ?? "null"
            return """
            {"iid": \(number), "title": "MR \(number) of \(group)", "draft": false,
             "web_url": "https://code.example.test/\(group)/app/-/merge_requests/\(number)",
             "updated_at": \(updated), "author": {"username": "marta"}}
            """
        }
        return Data("[\(items.joined(separator: ","))]".utf8)
    }

    // MARK: - GitHub pull requests

    @Test("GitHub: pull requests are searched within the owners, newest first")
    func githubPullsScoped() async throws {
        let (server, search, instance) = Self.gitHub()
        server.on("GET", "/api/v3/search/issues", fixture: "github-search-pulls")
        let pulls = try await search.searchPulls("retry", owners: ["octo", "ops"], on: instance, token: "test-token")

        let request = try #require(server.requests("GET", "/api/v3/search/issues").first)
        #expect(request.query["q"] == "retry is:pr is:open archived:false user:octo user:ops")
        #expect(request.query["sort"] == "updated")
        #expect(request.query["order"] == "desc")
        #expect(request.query["per_page"] == "10")
        #expect(request.header("Authorization") == "Bearer test-token")
        #expect(request.header("Accept") == "application/vnd.github+json")

        // The third item is an issue: its URL isn't a pull request's, so it is skipped.
        #expect(pulls.count == 2)
        let first = try #require(pulls.first)
        #expect(first.link == (try Self.link("octo/app", 482, on: instance)))
        #expect(first.link.instanceId == instance.id)
        #expect(first.title == "Retry the sync after a timeout")
        #expect(first.authorLogin == "marta")
        #expect(first.isDraft)
        #expect(first.updatedAt == (try Self.timestamp("2026-10-20T09:15:00Z")))
        let second = try #require(pulls.last)
        #expect(second.link == (try Self.link("ops/tools", 17, on: instance)))
        #expect(second.authorLogin == "ana")
        #expect(!second.isDraft)
    }

    @Test("GitHub: an instance of your own is searched without limiting the owners")
    func githubPullsOwnInstance() async throws {
        let (server, search, instance) = Self.gitHub()
        server.on("GET", "/api/v3/search/issues", fixture: "github-search-pulls")
        _ = try await search.searchPulls("retry", owners: nil, on: instance, token: "t")
        let request = try #require(server.requests("GET", "/api/v3/search/issues").first)
        #expect(request.query["q"] == "retry is:pr is:open archived:false")
    }

    @Test("GitHub: a missing draft flag is not a draft, and a missing author is empty")
    func githubPullsMissingFields() async throws {
        let (server, search, instance) = Self.gitHub()
        server.on("GET", "/api/v3/search/issues", body: Data("""
        {"items": [{"title": "Retry", "html_url": "https://ghe.example.test/octo/app/pull/3"}]}
        """.utf8))
        let pulls = try await search.searchPulls("retry", owners: nil, on: instance, token: "t")
        let pull = try #require(pulls.first)
        #expect(!pull.isDraft)
        #expect(pull.authorLogin == "")
        #expect(pull.updatedAt == nil)
    }

    @Test("GitHub: a pull request on another host than the instance's is skipped")
    func githubPullsForeignHost() async throws {
        let (server, search, instance) = Self.gitHub()
        server.on("GET", "/api/v3/search/issues", body: Data("""
        {"items": [{"title": "Retry", "html_url": "https://other.example.test/octo/app/pull/3"}]}
        """.utf8))
        #expect(try await search.searchPulls("retry", owners: nil, on: instance, token: "t").isEmpty)
    }

    // MARK: - GitHub repositories

    @Test("GitHub: repositories are searched within the owners")
    func githubRepos() async throws {
        let (server, search, instance) = Self.gitHub()
        server.on("GET", "/api/v3/search/repositories", fixture: "github-search-repos")
        let repos = try await search.searchRepos("retry", owners: ["octo"], on: instance, token: "test-token")

        let request = try #require(server.requests("GET", "/api/v3/search/repositories").first)
        #expect(request.query["q"] == "retry user:octo")
        #expect(request.query["sort"] == "updated")
        #expect(request.query["per_page"] == "10")
        #expect(request.header("Authorization") == "Bearer test-token")

        #expect(repos.map(\.host.slug) == ["octo/retry-kit", "ops/retry-tools"])
        #expect(repos.map(\.cloneURL) == ["https://ghe.example.test/octo/retry-kit.git",
                                          "https://ghe.example.test/ops/retry-tools.git"])
        #expect(repos.allSatisfy { $0.instanceId == instance.id })
        #expect(repos.first?.host == RemoteHost.make(fullName: "octo/retry-kit", on: instance))
    }

    @Test("GitHub: repositories on an instance of your own carry no owner")
    func githubReposOwnInstance() async throws {
        let (server, search, instance) = Self.gitHub()
        server.on("GET", "/api/v3/search/repositories", fixture: "github-search-repos")
        _ = try await search.searchRepos("retry", owners: nil, on: instance, token: "t")
        let request = try #require(server.requests("GET", "/api/v3/search/repositories").first)
        #expect(request.query["q"] == "retry")
    }

    // MARK: - GitLab merge requests

    @Test("GitLab: an instance of your own is searched across every project")
    func gitlabMRsOwnInstance() async throws {
        let (server, search, instance) = Self.gitLab()
        server.on("GET", "/api/v4/merge_requests", fixture: "gitlab-search-mrs")
        let pulls = try await search.searchPulls("retry", owners: nil, on: instance, token: "test-token")

        let request = try #require(server.requests("GET", "/api/v4/merge_requests").first)
        #expect(request.query["scope"] == "all")
        #expect(request.query["state"] == "opened")
        #expect(request.query["search"] == "retry")
        #expect(request.query["order_by"] == "updated_at")
        #expect(request.query["per_page"] == "10")
        #expect(request.header("Authorization") == "Bearer test-token")

        #expect(pulls.map(\.link) == [try Self.link("apps/payments/android/payments-app", 482, on: instance),
                                      try Self.link("apps/web/portal", 12, on: instance),
                                      try Self.link("apps/web/portal", 31, on: instance)])
        let first = try #require(pulls.first)
        #expect(first.title == "Retry the sync after a timeout")
        #expect(first.authorLogin == "marta")
        #expect(first.updatedAt == (try Self.timestamp("2026-10-20T09:15:00.481Z")))
        // `draft`, or the older `work_in_progress` when it is all the host sends.
        #expect(pulls.map(\.isDraft) == [false, true, true])
    }

    @Test("GitLab: gitlab.com is searched one group at a time, skipping a group that says 404")
    func gitlabMRsByGroup() async throws {
        let (server, search, instance) = Self.gitLab()
        server.on("GET", "/api/v4/groups/apps/merge_requests", fixture: "gitlab-search-mrs")
        server.on("GET", "/api/v4/groups/ops/merge_requests", status: 404, body: Data(#"{"message":"404 Group Not Found"}"#.utf8))
        let pulls = try await search.searchPulls("retry", owners: ["apps", "ops"], on: instance, token: "test-token")

        #expect(server.requests("GET", "/api/v4/merge_requests").isEmpty)
        let appsRequest = try #require(server.requests("GET", "/api/v4/groups/apps/merge_requests").first)
        #expect(server.requests("GET", "/api/v4/groups/ops/merge_requests").count == 1)
        #expect(appsRequest.query["state"] == "opened")
        #expect(appsRequest.query["search"] == "retry")
        #expect(appsRequest.query["order_by"] == "updated_at")
        #expect(appsRequest.query["per_page"] == "10")
        // Not `scope`: a group's merge requests are all of them by default.
        #expect(appsRequest.query["scope"] == nil)
        #expect(appsRequest.header("Authorization") == "Bearer test-token")

        // Newest update first, whatever order the host answered in.
        #expect(pulls.map(\.link.number) == [12, 482, 31])
    }

    @Test("GitLab: the groups' merge requests are merged by update date and cut at the limit")
    func gitlabMRsMergedAndCut() async throws {
        let (server, search, instance) = Self.gitLab()
        // Oldest first, so the order can't come from the hosts.
        server.on("GET", "/api/v4/groups/apps/merge_requests",
                  body: Self.mergeRequests(group: "apps", firstNumber: 1, minutes: [0, 10, 20, 30, 40, 50]))
        server.on("GET", "/api/v4/groups/ops/merge_requests",
                  body: Self.mergeRequests(group: "ops", firstNumber: 11, minutes: [5, 15, 25, 35, 45, 55]))
        let pulls = try await search.searchPulls("retry", owners: ["apps", "ops"], on: instance, token: "t")

        #expect(HostSearchFactory.resultLimit == 10)
        #expect(pulls.count == HostSearchFactory.resultLimit)
        #expect(pulls.map(\.link.number) == [16, 6, 15, 5, 14, 4, 13, 3, 12, 2])
    }

    @Test("GitLab: a merge request without a date goes last")
    func gitlabMRsUndatedLast() async throws {
        let (server, search, instance) = Self.gitLab()
        server.on("GET", "/api/v4/groups/apps/merge_requests",
                  body: Self.mergeRequests(group: "apps", firstNumber: 1, minutes: [nil, 10]))
        server.on("GET", "/api/v4/groups/ops/merge_requests",
                  body: Self.mergeRequests(group: "ops", firstNumber: 11, minutes: [20]))
        let pulls = try await search.searchPulls("retry", owners: ["apps", "ops"], on: instance, token: "t")
        #expect(pulls.map(\.link.number) == [11, 2, 1])
        #expect(pulls.last?.updatedAt == nil)
    }

    @Test("GitLab: a group that says 403 is skipped too; any other failure fails the search")
    func gitlabMRsGroupErrors() async throws {
        let forbidden = Self.gitLab()
        forbidden.server.on("GET", "/api/v4/groups/apps/merge_requests",
                            body: Self.mergeRequests(group: "apps", firstNumber: 1, minutes: [10]))
        forbidden.server.on("GET", "/api/v4/groups/ops/merge_requests", status: 403, body: Data("{}".utf8))
        let pulls = try await forbidden.search.searchPulls("retry", owners: ["apps", "ops"],
                                                           on: forbidden.instance, token: "t")
        #expect(pulls.map(\.link.number) == [1])

        let broken = Self.gitLab()
        broken.server.on("GET", "/api/v4/groups/apps/merge_requests",
                         body: Self.mergeRequests(group: "apps", firstNumber: 1, minutes: [10]))
        broken.server.on("GET", "/api/v4/groups/ops/merge_requests", status: 500, body: Data("boom".utf8))
        await #expect(throws: PullRequestFetchError.server(500, "boom")) {
            try await broken.search.searchPulls("retry", owners: ["apps", "ops"], on: broken.instance, token: "t")
        }
    }

    // MARK: - GitLab projects

    @Test("GitLab: projects are searched with the short form, most recently active first")
    func gitlabProjects() async throws {
        let (server, search, instance) = Self.gitLab()
        server.on("GET", "/api/v4/projects", fixture: "gitlab-search-projects")
        let repos = try await search.searchRepos("retry", owners: nil, on: instance, token: "test-token")

        let request = try #require(server.requests("GET", "/api/v4/projects").first)
        #expect(request.query["search"] == "retry")
        #expect(request.query["simple"] == "true")
        #expect(request.query["order_by"] == "last_activity_at")
        #expect(request.query["per_page"] == "10")
        #expect(request.query["membership"] == nil)
        #expect(request.header("Authorization") == "Bearer test-token")

        #expect(repos.map(\.host.slug) == ["apps/payments/android/payments-app", "apps/web/portal"])
        #expect(repos.map(\.host.owner) == ["apps/payments/android", "apps/web"])
        #expect(repos.map(\.cloneURL) == ["https://code.example.test/apps/payments/android/payments-app.git",
                                          "https://code.example.test/apps/web/portal.git"])
        #expect(repos.allSatisfy { $0.instanceId == instance.id })
    }

    @Test("GitLab: on gitlab.com the projects are only the account's")
    func gitlabProjectsMembership() async throws {
        let (server, search, instance) = Self.gitLab()
        server.on("GET", "/api/v4/projects", fixture: "gitlab-search-projects")
        _ = try await search.searchRepos("retry", owners: ["apps"], on: instance, token: "t")
        let request = try #require(server.requests("GET", "/api/v4/projects").first)
        #expect(request.query["membership"] == "true")
        #expect(request.query["search"] == "retry")
    }

    // MARK: - Text

    @Test("The text reaches the server as it was typed", arguments: [
        #"fix "retry" & más #12"#,
        "c++ 100% a=b?c",
    ])
    func escapedText(text: String) async throws {
        let gitHub = Self.gitHub()
        gitHub.server.on("GET", "/api/v3/search/issues", fixture: "github-search-pulls")
        gitHub.server.on("GET", "/api/v3/search/repositories", fixture: "github-search-repos")
        _ = try await gitHub.search.searchPulls(text, owners: nil, on: gitHub.instance, token: "t")
        _ = try await gitHub.search.searchRepos(text, owners: nil, on: gitHub.instance, token: "t")
        #expect(gitHub.server.requests("GET", "/api/v3/search/issues").first?.query["q"]
                == "\(text) is:pr is:open archived:false")
        #expect(gitHub.server.requests("GET", "/api/v3/search/repositories").first?.query["q"] == text)

        let gitLab = Self.gitLab()
        gitLab.server.on("GET", "/api/v4/merge_requests", fixture: "gitlab-search-mrs")
        gitLab.server.on("GET", "/api/v4/groups/apps/merge_requests", fixture: "gitlab-search-mrs")
        gitLab.server.on("GET", "/api/v4/projects", fixture: "gitlab-search-projects")
        _ = try await gitLab.search.searchPulls(text, owners: nil, on: gitLab.instance, token: "t")
        _ = try await gitLab.search.searchPulls(text, owners: ["apps"], on: gitLab.instance, token: "t")
        _ = try await gitLab.search.searchRepos(text, owners: nil, on: gitLab.instance, token: "t")
        #expect(gitLab.server.requests("GET", "/api/v4/merge_requests").first?.query["search"] == text)
        #expect(gitLab.server.requests("GET", "/api/v4/groups/apps/merge_requests").first?.query["search"] == text)
        #expect(gitLab.server.requests("GET", "/api/v4/projects").first?.query["search"] == text)
    }

    @Test("Spaces around the text are not searched for")
    func textIsTrimmed() async throws {
        let gitHub = Self.gitHub()
        gitHub.server.on("GET", "/api/v3/search/issues", fixture: "github-search-pulls")
        _ = try await gitHub.search.searchPulls("  retry \n", owners: ["octo"], on: gitHub.instance, token: "t")
        #expect(gitHub.server.requests("GET", "/api/v3/search/issues").first?.query["q"]
                == "retry is:pr is:open archived:false user:octo")

        let gitLab = Self.gitLab()
        gitLab.server.on("GET", "/api/v4/projects", fixture: "gitlab-search-projects")
        _ = try await gitLab.search.searchRepos(" retry ", owners: nil, on: gitLab.instance, token: "t")
        #expect(gitLab.server.requests("GET", "/api/v4/projects").first?.query["search"] == "retry")
    }

    @Test("A text of nothing but spaces asks the host nothing")
    func blankTextAsksNothing() async throws {
        let gitHub = Self.gitHub()
        #expect(try await gitHub.search.searchPulls(" \n ", owners: ["octo"], on: gitHub.instance, token: "t").isEmpty)
        #expect(try await gitHub.search.searchRepos("", owners: nil, on: gitHub.instance, token: "t").isEmpty)
        #expect(gitHub.server.requests.isEmpty)

        let gitLab = Self.gitLab()
        #expect(try await gitLab.search.searchPulls("  ", owners: nil, on: gitLab.instance, token: "t").isEmpty)
        #expect(try await gitLab.search.searchPulls("  ", owners: ["apps"], on: gitLab.instance, token: "t").isEmpty)
        #expect(try await gitLab.search.searchRepos(" ", owners: nil, on: gitLab.instance, token: "t").isEmpty)
        #expect(gitLab.server.requests.isEmpty)
    }

    // MARK: - Current path

    @Test("GitHub: a repo's current path is the full name it answers with")
    func currentPathGitHub() async throws {
        let (server, search, instance) = Self.gitHub()
        // The host redirects the old name; the session follows it and this is where it ends.
        server.on("GET", "/api/v3/repos/octo/old-name", fixture: "github-repo")
        let host = try #require(RemoteHost.make(fullName: "octo/old-name", on: instance))
        let path = try await search.currentPath(of: host, token: "test-token")
        #expect(path == "octo/new-name")
        let request = try #require(server.requests("GET", "/api/v3/repos/octo/old-name").first)
        #expect(request.header("Authorization") == "Bearer test-token")
    }

    @Test("GitLab: a project's current path is the one it answers with, asked by its encoded old path")
    func currentPathGitLab() async throws {
        let (server, search, instance) = Self.gitLab()
        server.on("GET", "/api/v4/projects/team/old", fixture: "gitlab-project")
        let host = try #require(RemoteHost.make(fullName: "team/old", on: instance))
        let path = try await search.currentPath(of: host, token: "test-token")
        #expect(path == "team/new")
        let request = try #require(server.requests("GET", "/api/v4/projects/team/old").first)
        #expect(request.header("Authorization") == "Bearer test-token")
    }

    @Test("A repo the host doesn't know any more has no current path")
    func currentPathNotFound() async throws {
        let gitHub = Self.gitHub()
        gitHub.server.on("GET", "/api/v3/repos/octo/gone", status: 404, body: Data(#"{"message":"Not Found"}"#.utf8))
        let gitHubHost = try #require(RemoteHost.make(fullName: "octo/gone", on: gitHub.instance))
        #expect(try await gitHub.search.currentPath(of: gitHubHost, token: "t") == nil)

        let gitLab = Self.gitLab()
        gitLab.server.on("GET", "/api/v4/projects/team/gone", status: 404, body: Data(#"{"message":"404 Project Not Found"}"#.utf8))
        let gitLabHost = try #require(RemoteHost.make(fullName: "team/gone", on: gitLab.instance))
        #expect(try await gitLab.search.currentPath(of: gitLabHost, token: "t") == nil)
    }

    @Test("A server error is not an answer about the path")
    func currentPathServerError() async throws {
        let gitHub = Self.gitHub()
        gitHub.server.on("GET", "/api/v3/repos/octo/app", status: 500, body: Data("boom".utf8))
        let gitHubHost = try #require(RemoteHost.make(fullName: "octo/app", on: gitHub.instance))
        await #expect(throws: PullRequestFetchError.server(500, "boom")) {
            try await gitHub.search.currentPath(of: gitHubHost, token: "t")
        }

        let gitLab = Self.gitLab()
        gitLab.server.on("GET", "/api/v4/projects/team/app", status: 500, body: Data("boom".utf8))
        let gitLabHost = try #require(RemoteHost.make(fullName: "team/app", on: gitLab.instance))
        await #expect(throws: PullRequestFetchError.server(500, "boom")) {
            try await gitLab.search.currentPath(of: gitLabHost, token: "t")
        }
    }

    @Test("A project in nested groups is asked by its whole path")
    func currentPathNestedGroups() async throws {
        let (server, search, instance) = Self.gitLab()
        server.on("GET", "/api/v4/projects/apps/payments/android/payments-app", fixture: "gitlab-project")
        let host = try #require(RemoteHost.make(fullName: "apps/payments/android/payments-app", on: instance))
        #expect(try await search.currentPath(of: host, token: "t") == "team/new")
    }

    // MARK: - Failures

    @Test("A 401 from any call is unauthorized, so the caller can refresh the token")
    func unauthorized() async throws {
        let gitHub = Self.gitHub()
        gitHub.server.on("GET", "/api/v3/search/issues", status: 401, body: Data("{}".utf8))
        gitHub.server.on("GET", "/api/v3/search/repositories", status: 401, body: Data("{}".utf8))
        gitHub.server.on("GET", "/api/v3/repos/octo/app", status: 401, body: Data("{}".utf8))
        let gitHubHost = try #require(RemoteHost.make(fullName: "octo/app", on: gitHub.instance))
        await #expect(throws: PullRequestFetchError.unauthorized) {
            try await gitHub.search.searchPulls("retry", owners: nil, on: gitHub.instance, token: "t")
        }
        await #expect(throws: PullRequestFetchError.unauthorized) {
            try await gitHub.search.searchRepos("retry", owners: nil, on: gitHub.instance, token: "t")
        }
        await #expect(throws: PullRequestFetchError.unauthorized) {
            try await gitHub.search.currentPath(of: gitHubHost, token: "t")
        }

        let gitLab = Self.gitLab()
        gitLab.server.on("GET", "/api/v4/merge_requests", status: 401, body: Data("{}".utf8))
        gitLab.server.on("GET", "/api/v4/groups/apps/merge_requests", status: 401, body: Data("{}".utf8))
        gitLab.server.on("GET", "/api/v4/projects", status: 401, body: Data("{}".utf8))
        gitLab.server.on("GET", "/api/v4/projects/team/app", status: 401, body: Data("{}".utf8))
        let gitLabHost = try #require(RemoteHost.make(fullName: "team/app", on: gitLab.instance))
        await #expect(throws: PullRequestFetchError.unauthorized) {
            try await gitLab.search.searchPulls("retry", owners: nil, on: gitLab.instance, token: "t")
        }
        await #expect(throws: PullRequestFetchError.unauthorized) {
            try await gitLab.search.searchPulls("retry", owners: ["apps"], on: gitLab.instance, token: "t")
        }
        await #expect(throws: PullRequestFetchError.unauthorized) {
            try await gitLab.search.searchRepos("retry", owners: nil, on: gitLab.instance, token: "t")
        }
        await #expect(throws: PullRequestFetchError.unauthorized) {
            try await gitLab.search.currentPath(of: gitLabHost, token: "t")
        }
    }

    @Test("An answer that isn't the expected shape is a decoding error")
    func decodingFailure() async throws {
        let gitHub = Self.gitHub()
        gitHub.server.on("GET", "/api/v3/search/issues", body: Data(#"{"nope": 1}"#.utf8))
        gitHub.server.on("GET", "/api/v3/search/repositories", body: Data(#"{"nope": 1}"#.utf8))
        let gitLab = Self.gitLab()
        gitLab.server.on("GET", "/api/v4/merge_requests", body: Data(#"{"nope": 1}"#.utf8))
        gitLab.server.on("GET", "/api/v4/projects", body: Data(#"{"nope": 1}"#.utf8))

        func isDecoding(_ error: Error) -> Bool {
            if case .decoding = error as? PullRequestFetchError { return true }
            return false
        }
        await #expect { try await gitHub.search.searchPulls("retry", owners: nil, on: gitHub.instance, token: "t") } throws: { isDecoding($0) }
        await #expect { try await gitHub.search.searchRepos("retry", owners: nil, on: gitHub.instance, token: "t") } throws: { isDecoding($0) }
        await #expect { try await gitLab.search.searchPulls("retry", owners: nil, on: gitLab.instance, token: "t") } throws: { isDecoding($0) }
        await #expect { try await gitLab.search.searchRepos("retry", owners: nil, on: gitLab.instance, token: "t") } throws: { isDecoding($0) }
    }

    @Test("The factory picks the client for the instance kind")
    func factory() {
        #expect(HostSearchFactory.make(for: .github) is GitHubHostSearch)
        #expect(HostSearchFactory.make(for: .gitlab) is GitLabHostSearch)
    }
}
