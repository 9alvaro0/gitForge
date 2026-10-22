import Foundation
import Testing
@testable import gitForge

@Suite("Review activity")
@MainActor
struct ReviewActivitySourceTests {
    static let since = Date(timeIntervalSince1970: 1_790_000_000)

    @Test("GitLab reads events after the date and pages until a short page")
    func gitlabEvents() async throws {
        let server = StubServer()
        server.on("GET", "/api/v4/events", fixture: "gitlab-events")
        let source = GitLabReviewActivity(session: server.http.session)
        let hits = try await source.recentActivity(apiBase: try #require(URL(string: "https://\(server.host)/api/v4")),
                                                   login: "marta", since: Self.since, token: "test-token")
        #expect(Set(hits.map(\.ref)) == [.projectId("11"), .projectId("12")])
        let request = try #require(server.requests("GET", "/api/v4/events").first)
        #expect(request.query["after"] == "2026-09-21")
        #expect(request.query["per_page"] == "100")
        #expect(server.requests("GET", "/api/v4/events").count == 1)
    }

    @Test("GitHub searches the account's pull requests updated since the date")
    func githubSearch() async throws {
        let server = StubServer()
        server.on("GET", "/api/v3/search/issues", fixture: "github-search-prs")
        let source = GitHubReviewActivity(session: server.http.session)
        let hits = try await source.recentActivity(apiBase: try #require(URL(string: "https://\(server.host)/api/v3")),
                                                   login: "octo", since: Self.since, token: "test-token")
        #expect(Set(hits.map(\.ref)) == [.path("octo/app"), .path("oss/lib")])
        let request = try #require(server.requests("GET", "/api/v3/search/issues").first)
        #expect(request.query["q"] == "is:pr involves:octo updated:>=2026-09-21")
        // The one page keeps the most recently updated pull requests.
        #expect(request.query["sort"] == "updated")
        #expect(request.query["order"] == "desc")
    }

    @Test("Only member repos count, each with its newest hit")
    func matcher() {
        let member = RemoteRepoSummary(id: "11", name: "app", fullName: "team/app", description: nil, sshURL: nil,
                                       httpsURL: "https://gitlab.example.test/team/app.git", isPrivate: true, defaultBranch: "main")
        let hits = [ActivityHit(ref: .projectId("11"), at: Date(timeIntervalSince1970: 5)),
                    ActivityHit(ref: .projectId("11"), at: Date(timeIntervalSince1970: 9)),
                    ActivityHit(ref: .projectId("99"), at: Date(timeIntervalSince1970: 7))]
        let matched = ActivityMatcher.match(hits, members: [member])
        #expect(matched.map(\.summary.fullName) == ["team/app"])
        #expect(matched.first?.at == Date(timeIntervalSince1970: 9))
    }

    // MARK: - GitLab details

    @Test("GitLab keeps each event's project and time, and sends the bearer token")
    func gitlabHitsAndHeaders() async throws {
        let server = StubServer()
        server.on("GET", "/api/v4/events", fixture: "gitlab-events")
        let source = GitLabReviewActivity(session: server.http.session)
        let hits = try await source.recentActivity(apiBase: try #require(URL(string: "https://\(server.host)/api/v4")),
                                                   login: "marta", since: Self.since, token: "test-token")
        #expect(hits.count == 3)
        let newestIn11 = hits.filter { $0.ref == .projectId("11") }.map(\.at).max()
        #expect(newestIn11 == RemoteAPI.parseTimestamp("2026-10-14T09:30:12.481Z"))
        let request = try #require(server.requests("GET", "/api/v4/events").first)
        #expect(request.header("Authorization") == "Bearer test-token")
        #expect(request.query["page"] == "1")
    }

    @Test("GitLab asks for the next page while the previous one is full")
    func gitlabPaging() async throws {
        let server = StubServer()
        server.on("GET", "/api/v4/events", body: Self.eventsPage(count: 100, projectId: 11))
        server.on("GET", "/api/v4/events", body: Self.eventsPage(count: 1, projectId: 12))
        let source = GitLabReviewActivity(session: server.http.session)
        let hits = try await source.recentActivity(apiBase: try #require(URL(string: "https://\(server.host)/api/v4")),
                                                   login: "marta", since: Self.since, token: "test-token")
        #expect(hits.count == 101)
        #expect(Set(hits.map(\.ref)) == [.projectId("11"), .projectId("12")])
        #expect(server.requests("GET", "/api/v4/events").map { $0.query["page"] } == ["1", "2"])
    }

    @Test("GitLab stops after five pages even if they are all full")
    func gitlabPageCap() async throws {
        let server = StubServer()
        server.on("GET", "/api/v4/events", body: Self.eventsPage(count: 100, projectId: 11))
        let source = GitLabReviewActivity(session: server.http.session)
        let hits = try await source.recentActivity(apiBase: try #require(URL(string: "https://\(server.host)/api/v4")),
                                                   login: "marta", since: Self.since, token: "test-token")
        #expect(hits.count == 500)
        #expect(server.requests("GET", "/api/v4/events").map { $0.query["page"] } == ["1", "2", "3", "4", "5"])
    }

    @Test("GitLab ignores events without a project or a usable date")
    func gitlabSkipsUnusableEvents() async throws {
        let server = StubServer()
        server.on("GET", "/api/v4/events", body: Data("""
        [{"id": 1, "project_id": null, "created_at": "2026-10-14T09:30:12.000Z"},
         {"id": 2, "project_id": 11, "created_at": "yesterday"},
         {"id": 3, "project_id": 12, "created_at": "2026-10-14T09:30:12.000Z"}]
        """.utf8))
        let source = GitLabReviewActivity(session: server.http.session)
        let hits = try await source.recentActivity(apiBase: try #require(URL(string: "https://\(server.host)/api/v4")),
                                                   login: "marta", since: Self.since, token: "test-token")
        #expect(hits.map(\.ref) == [.projectId("12")])
    }

    // MARK: - GitHub details

    @Test("GitHub keeps each item's repository and time, and sends the bearer token")
    func githubHitsAndHeaders() async throws {
        let server = StubServer()
        server.on("GET", "/api/v3/search/issues", fixture: "github-search-prs")
        let source = GitHubReviewActivity(session: server.http.session)
        let hits = try await source.recentActivity(apiBase: try #require(URL(string: "https://\(server.host)/api/v3")),
                                                   login: "octo", since: Self.since, token: "test-token")
        #expect(hits.count == 3)
        let newestInApp = hits.filter { $0.ref == .path("octo/app") }.map(\.at).max()
        #expect(newestInApp == RemoteAPI.parseTimestamp("2026-10-15T10:20:30Z"))
        let request = try #require(server.requests("GET", "/api/v3/search/issues").first)
        #expect(request.header("Authorization") == "Bearer test-token")
        #expect(request.query["per_page"] == "100")
        #expect(server.requests("GET", "/api/v3/search/issues").count == 1)
    }

    @Test("GitHub ignores items without a usable repository or date")
    func githubSkipsUnusableItems() async throws {
        let server = StubServer()
        server.on("GET", "/api/v3/search/issues", body: Data("""
        {"total_count": 3, "items": [
          {"repository_url": "https://api.github.com/repos/octo", "updated_at": "2026-10-15T10:20:30Z"},
          {"repository_url": "https://api.github.com/repos/octo/app", "updated_at": "recently"},
          {"repository_url": "https://api.github.com/repos/oss/lib", "updated_at": "2026-10-15T10:20:30Z"}]}
        """.utf8))
        let source = GitHubReviewActivity(session: server.http.session)
        let hits = try await source.recentActivity(apiBase: try #require(URL(string: "https://\(server.host)/api/v3")),
                                                   login: "octo", since: Self.since, token: "test-token")
        #expect(hits.map(\.ref) == [.path("oss/lib")])
    }

    @Test("A 401 is reported as unauthorized")
    func unauthorized() async throws {
        let server = StubServer()
        server.on("GET", "/api/v3/search/issues", status: 401, body: Data("{}".utf8))
        let source = ReviewActivitySourceFactory.make(for: .github, session: server.http.session)
        let apiBase = try #require(URL(string: "https://\(server.host)/api/v3"))
        await #expect(throws: PullRequestFetchError.unauthorized) {
            try await source.recentActivity(apiBase: apiBase, login: "octo", since: Self.since, token: "test-token")
        }
    }

    @Test("A body that isn't the expected JSON is a decoding error")
    func decodingFailure() async throws {
        let server = StubServer()
        server.on("GET", "/api/v4/events", body: Data("{\"message\": \"nope\"}".utf8))
        let source = ReviewActivitySourceFactory.make(for: .gitlab, session: server.http.session)
        let apiBase = try #require(URL(string: "https://\(server.host)/api/v4"))
        do {
            _ = try await source.recentActivity(apiBase: apiBase, login: "marta", since: Self.since, token: "test-token")
            Issue.record("Expected a decoding error")
        } catch PullRequestFetchError.decoding {
            // expected
        }
    }

    @Test("The factory picks the source for the instance kind")
    func factory() {
        #expect(ReviewActivitySourceFactory.make(for: .github) is GitHubReviewActivity)
        #expect(ReviewActivitySourceFactory.make(for: .gitlab) is GitLabReviewActivity)
    }

    // MARK: - Matcher details

    @Test("GitHub matches the repo's full name without regard to case")
    func matcherIgnoresCaseForPaths() {
        let member = Self.summary(id: "501", fullName: "Octo/App")
        let hits = [ActivityHit(ref: .path("octo/app"), at: Date(timeIntervalSince1970: 3)),
                    ActivityHit(ref: .path("OCTO/APP"), at: Date(timeIntervalSince1970: 8)),
                    ActivityHit(ref: .path("oss/lib"), at: Date(timeIntervalSince1970: 20))]
        let matched = ActivityMatcher.match(hits, members: [member])
        #expect(matched.map(\.summary.id) == ["501"])
        #expect(matched.first?.at == Date(timeIntervalSince1970: 8))
    }

    @Test("Matches come back in member order, once per repo")
    func matcherKeepsMemberOrderAndDedupes() {
        let first = Self.summary(id: "11", fullName: "team/app")
        let second = Self.summary(id: "12", fullName: "team/lib")
        let third = Self.summary(id: "13", fullName: "team/idle")
        let hits = [ActivityHit(ref: .projectId("12"), at: Date(timeIntervalSince1970: 4)),
                    ActivityHit(ref: .projectId("11"), at: Date(timeIntervalSince1970: 6))]
        let matched = ActivityMatcher.match(hits, members: [first, second, third, first])
        #expect(matched.map(\.summary.id) == ["11", "12"])
        #expect(matched.map(\.at) == [Date(timeIntervalSince1970: 6), Date(timeIntervalSince1970: 4)])
    }

    @Test("No members or no hits means no matches")
    func matcherEmpty() {
        let member = Self.summary(id: "11", fullName: "team/app")
        #expect(ActivityMatcher.match([], members: [member]).isEmpty)
        #expect(ActivityMatcher.match([ActivityHit(ref: .projectId("11"), at: .now)], members: []).isEmpty)
    }

    // MARK: - Helpers

    private static func summary(id: String, fullName: String) -> RemoteRepoSummary {
        RemoteRepoSummary(id: id, name: String(fullName.split(separator: "/").last ?? ""), fullName: fullName,
                          description: nil, sshURL: nil, httpsURL: "https://gitlab.example.test/\(fullName).git",
                          isPrivate: true, defaultBranch: "main")
    }

    private static func eventsPage(count: Int, projectId: Int) -> Data {
        let events = (0..<count).map { index in
            "{\"id\": \(index + 1), \"project_id\": \(projectId), \"created_at\": \"2026-10-14T09:30:12.000Z\"}"
        }
        return Data("[\(events.joined(separator: ","))]".utf8)
    }
}
