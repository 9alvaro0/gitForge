import Foundation
import Testing
@testable import gitForge

@Suite("RemoteRepoBrowser — instance API")
@MainActor
struct RemoteRepoBrowserTests {

    @Test("GitHub lists /user/repos under the instance API base with a bearer token")
    func github() async throws {
        let server = StubServer()
        server.on("GET", "/api/v3/user/repos", fixture: "github-repos")
        let browser = GitHubRepoBrowser(session: server.http.session)
        let repos = try await browser.fetchUserRepos(apiBase: try #require(URL(string: "https://\(server.host)/api/v3")),
                                                     token: "test-token", page: 1)
        #expect(repos.map(\.fullName) == ["octo/app"])
        #expect(repos.first?.httpsURL == "https://github.com/octo/app.git")
        #expect(repos.first?.isPrivate == true)
        let request = try #require(server.requests("GET", "/api/v3/user/repos").first)
        #expect(request.header("Authorization") == "Bearer test-token")
    }

    @Test("GitLab lists /projects?membership under a custom API base")
    func gitlab() async throws {
        let server = StubServer()
        server.on("GET", "/gitlab/api/v4/projects", fixture: "gitlab-projects")
        let browser = GitLabRepoBrowser(session: server.http.session)
        let repos = try await browser.fetchUserRepos(apiBase: try #require(URL(string: "https://\(server.host)/gitlab/api/v4")),
                                                     token: "test-token", page: 1)
        #expect(repos.map(\.fullName) == ["group/sub/app"])
        #expect(repos.first?.httpsURL == "https://git.empresa.com/group/sub/app.git")
        #expect(server.requests("GET", "/gitlab/api/v4/projects").first?.header("Authorization") == "Bearer test-token")
    }

    @Test("A 401 is reported as unauthorized")
    func unauthorized() async throws {
        let server = StubServer()
        server.on("GET", "/api/v3/user/repos", status: 401, body: Data("{}".utf8))
        let browser = RemoteRepoBrowserFactory.make(for: .github, session: server.http.session)
        let apiBase = try #require(URL(string: "https://\(server.host)/api/v3"))
        await #expect(throws: PullRequestFetchError.unauthorized) {
            try await browser.fetchUserRepos(apiBase: apiBase, token: "test-token", page: 1)
        }
    }
}
