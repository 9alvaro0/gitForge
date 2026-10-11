import Foundation
import Testing
@testable import gitForge

@Suite("RemoteHost — declared instances")
struct RemoteHostInstanceTests {
    static let empresa = HostingInstance(kind: .gitlab, host: "git.empresa.com",
                                         apiBaseURL: URL(string: "https://git.empresa.com/gitlab/api/v4"))
    static let ghe = HostingInstance(kind: .github, host: "ghe.corp.test")

    @Test("A declared instance with its own domain is recognised, with its API base")
    func customDomain() throws {
        #expect(RemoteHost.parse("https://git.empresa.com/group/app.git") == nil)
        let host = try #require(RemoteHost.parse("https://git.empresa.com/group/sub/app.git", instances: [Self.empresa]))
        #expect(host.provider == .gitlab)
        #expect(host.owner == "group/sub")
        #expect(host.repo == "app")
        #expect(host.apiBaseURL?.absoluteString == "https://git.empresa.com/gitlab/api/v4")
        let enterprise = try #require(RemoteHost.parse("git@ghe.corp.test:org/app.git", instances: [Self.ghe]))
        #expect(enterprise.provider == .github)
        #expect(enterprise.owner == "org")
        #expect(enterprise.apiBaseURL?.absoluteString == "https://ghe.corp.test/api/v3")
    }

    @Test("Without a declared instance the host-name guess still works")
    func fallback() {
        let host = RemoteHost.parse("https://gitlab.com/group/app.git", instances: [])
        #expect(host?.provider == .gitlab)
        #expect(host?.apiBaseURL == nil)
    }

    @Test("Providers use the instance API base, and GitLab sends a bearer token")
    func providers() throws {
        let gitlab = try #require(RemoteHost.parse("https://git.empresa.com/group/app.git", instances: [Self.empresa]))
        #expect(GitLabPullRequestProvider.base(for: gitlab) == "https://git.empresa.com/gitlab/api/v4")
        #expect(GitLabPullRequestProvider.base(for: RemoteHost(provider: .gitlab, host: "gitlab.com", owner: "g", repo: "a"))
                == "https://gitlab.com/api/v4")
        #expect(GitHubPullRequestProvider.base(for: RemoteHost(provider: .github, host: "github.com", owner: "o", repo: "a"))
                == "https://api.github.com")
        let request = GitLabPullRequestProvider.makeRequest(url: URL(string: "https://gitlab.com/api/v4/user"), token: "test-token")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        #expect(request.value(forHTTPHeaderField: "PRIVATE-TOKEN") == nil)
    }
}
