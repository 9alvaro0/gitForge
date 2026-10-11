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
        #expect(RemoteHost.parse("https://git.empresa.com/group/app.git", instances: []) == nil)
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

    @Test("An undeclared host isn't recognised; a GitHub/GitLab-looking one is offered as an instance")
    func undeclared() {
        let url = "https://gitlab.example.org/group/app.git"
        #expect(RemoteHost.parse(url, instances: HostingInstance.builtIns) == nil)
        #expect(RemoteHost.suggestedInstance(forRemoteURL: url, instances: HostingInstance.builtIns)
                == InstanceSuggestion(host: "gitlab.example.org", kind: .gitlab))
        #expect(RemoteHost.suggestedInstance(forRemoteURL: "git@ghe.github.com:org/app.git", instances: [])
                == InstanceSuggestion(host: "ghe.github.com", kind: .github))
        #expect(RemoteHost.suggestedInstance(forRemoteURL: "https://git.empresa.com/group/app.git", instances: []) == nil)
        // Declared: recognised, so nothing to propose.
        #expect(RemoteHost.parse("https://gitlab.com/group/app.git", instances: HostingInstance.builtIns)?.provider == .gitlab)
        #expect(RemoteHost.suggestedInstance(forRemoteURL: "https://gitlab.com/group/app.git",
                                             instances: HostingInstance.builtIns) == nil)
    }

    @Test("The repo's origin is read and recognised against the instances")
    func gitRemote() async throws {
        let repo = try GitTestRepo()
        defer { repo.remove() }
        try repo.git("remote", "add", "origin", "https://git.empresa.com/group/app.git")
        let cli = GitCLI(workingDirectory: repo.url)
        #expect(await cli.remoteHost(instances: []) == nil)
        #expect(await cli.remoteHost(instances: [Self.empresa])?.owner == "group")
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
