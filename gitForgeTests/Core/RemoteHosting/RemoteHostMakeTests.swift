import Foundation
import Testing
@testable import gitForge

@Suite("RemoteHost.make")
struct RemoteHostMakeTests {
    @Test("GitLab keeps nested groups as the owner and takes the instance's API base")
    func gitlabNested() throws {
        let instance = HostingInstance(kind: .gitlab, host: "gitlab.example.test",
                                       apiBaseURL: URL(string: "https://gitlab.example.test/api/v4"))
        let host = try #require(RemoteHost.make(fullName: "apps/payments/android/payments-app", on: instance))
        #expect(host.provider == .gitlab)
        #expect(host.owner == "apps/payments/android")
        #expect(host.repo == "payments-app")
        #expect(host.apiBaseURL == instance.apiBaseURL)
    }

    @Test("GitHub needs exactly owner/repo")
    func github() {
        #expect(RemoteHost.make(fullName: "octo/app", on: .gitHubDotCom)?.slug == "octo/app")
        #expect(RemoteHost.make(fullName: "octo/app/extra", on: .gitHubDotCom) == nil)
        #expect(RemoteHost.make(fullName: "app", on: .gitLabDotCom) == nil)
    }

    @Test("A pull request survives a JSON round trip")
    func pullCodable() throws {
        let pull = PullRequest(id: "1", number: 7, title: "Retry", state: .draft, authorLogin: "marta", authorAvatarURL: nil,
                               sourceBranch: "fix/retry", targetBranch: "main", webURL: nil, createdAt: nil,
                               updatedAt: Date(timeIntervalSince1970: 100), headSha: "abc")
        let data = try JSONEncoder().encode(pull)
        #expect(try JSONDecoder().decode(PullRequest.self, from: data) == pull)
    }

    @Test("Pull request states are stored under stable names")
    func stateRawValues() {
        let raw = [PullRequest.State.open, .closed, .merged, .draft].map(\.rawValue)
        #expect(raw == ["open", "closed", "merged", "draft"])
    }

    @Test("A remote host and a repo summary survive a JSON round trip")
    func hostAndSummaryCodable() throws {
        let instance = HostingInstance(kind: .gitlab, host: "gitlab.example.test")
        let host = try #require(RemoteHost.make(fullName: "apps/payments/payments-app", on: instance))
        let summary = RemoteRepoSummary(id: "42", name: "payments-app", fullName: "apps/payments/payments-app",
                                        description: nil, sshURL: nil,
                                        httpsURL: "https://gitlab.example.test/apps/payments/payments-app.git",
                                        isPrivate: true, defaultBranch: "main")
        #expect(try JSONDecoder().decode(RemoteHost.self, from: JSONEncoder().encode(host)) == host)
        #expect(try JSONDecoder().decode(RemoteRepoSummary.self, from: JSONEncoder().encode(summary)) == summary)
    }
}
