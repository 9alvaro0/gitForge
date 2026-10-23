import Foundation
import Testing
@testable import gitForge

@Suite("Pull request links")
struct PullRequestLinkTests {
    static let gitlab = HostingInstance(kind: .gitlab, host: "gitlab.example.test")
    static let instances = [HostingInstance.gitHubDotCom, gitlab]

    @Test("A GitLab merge request link, with nested groups and whatever follows the number", arguments: [
        "https://gitlab.example.test/apps/payments/android/payments-app/-/merge_requests/482",
        "https://gitlab.example.test/apps/payments/android/payments-app/-/merge_requests/482/diffs?commit_id=abc#note_9",
        "  http://GITLAB.example.test/apps/payments/android/payments-app/merge_requests/482\n",
    ])
    func gitlab(text: String) throws {
        let link = try #require(PullRequestLink.parse(text, instances: Self.instances))
        #expect(link.host.host == "gitlab.example.test")
        #expect(link.host.owner == "apps/payments/android")
        #expect(link.host.repo == "payments-app")
        #expect(link.host.provider == .gitlab)
        #expect(link.number == 482)
        #expect(link.instanceId == Self.gitlab.id)
    }

    @Test("A GitHub pull request link", arguments: [
        "https://github.com/octo/app/pull/7", "https://www.github.com/octo/app/pull/7/files#diff-1",
    ])
    func github(text: String) throws {
        let link = try #require(PullRequestLink.parse(text, instances: Self.instances))
        #expect(link.host.slug == "octo/app")
        #expect(link.host.provider == .github)
        #expect(link.number == 7)
    }

    @Test("Anything else isn't a link", arguments: [
        "482", "https://github.com/octo/app/pulls", "https://github.com/octo/app/pull/0",
        "https://github.com/octo/app/pull/abc", "https://github.com/octo/app/issues/7",
        "https://github.com/octo/app/-/merge_requests/3", "https://gitlab.example.test/team/app/pull/3",
        "https://gitlab.example.test/-/merge_requests/3", "git@github.com:octo/app.git",
        "https://code.example.test/team/app/-/merge_requests/5",
        // A file's path that happens to hold `merge_requests/<N>`, past the `/-/` that ends the repo.
        "https://gitlab.example.test/team/app/-/blob/main/merge_requests/5",
    ])
    func notALink(text: String) {
        #expect(PullRequestLink.parse(text, instances: Self.instances) == nil)
    }

    @Test("An undeclared host is offered as an instance of the kind its URL shows")
    func suggestion() {
        #expect(PullRequestLink.suggestion(for: "https://code.example.test/team/app/-/merge_requests/5",
                                           instances: Self.instances) == InstanceSuggestion(host: "code.example.test", kind: .gitlab))
        #expect(PullRequestLink.suggestion(for: "https://ghe.example.test/octo/app/pull/9",
                                           instances: Self.instances) == InstanceSuggestion(host: "ghe.example.test", kind: .github))
        #expect(PullRequestLink.suggestion(for: "https://github.com/octo/app/pull/7", instances: Self.instances) == nil)
        #expect(PullRequestLink.suggestion(for: "https://code.example.test/team/app", instances: Self.instances) == nil)
        #expect(PullRequestLink.suggestion(for: "https://code.example.test/team/app/-/blob/main/merge_requests/5",
                                           instances: Self.instances) == nil)
    }
}
