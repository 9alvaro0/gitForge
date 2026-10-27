import Foundation
import Testing
@testable import gitForge

@Suite("PR providers — the list's verdicts")
@MainActor
struct PullListStatusParsingTests {

    private static func data(_ json: String) -> Data { Data(json.utf8) }

    // MARK: GitLab

    @Test("GitLab list: an open merge request takes its detailed_merge_status; a draft and a merged one don't")
    func gitLabList() throws {
        let pulls = try GitLabPullRequestProvider.parseList(Self.data("""
        [{"id": 1, "iid": 10, "title": "A", "state": "opened", "source_branch": "a", "target_branch": "main",
          "detailed_merge_status": "blocked_status", "merge_status": "can_be_merged", "has_conflicts": false},
         {"id": 2, "iid": 11, "title": "B", "state": "opened", "source_branch": "b", "target_branch": "main",
          "merge_status": "cannot_be_merged"},
         {"id": 3, "iid": 12, "title": "C", "state": "opened", "draft": true, "source_branch": "c",
          "target_branch": "main", "detailed_merge_status": "draft_status"},
         {"id": 4, "iid": 13, "title": "D", "state": "merged", "source_branch": "d", "target_branch": "main",
          "detailed_merge_status": "not_open"},
         {"id": 5, "iid": 14, "title": "E", "state": "opened", "source_branch": "e", "target_branch": "main"}]
        """))
        #expect(pulls.map(\.listStatus) == [PullListStatus(kind: .blocked, hostCode: "blocked_status"),
                                            PullListStatus(kind: .conflicts, hostCode: "cannot_be_merged"),
                                            nil, nil, nil])
        #expect(pulls[2].state == .draft)
    }

    // MARK: GitHub

    @Test("GitHub GraphQL: each node's verdict by number; drafts and null nodes are left out")
    func gitHubStatuses() throws {
        let statuses = try GitHubPullRequestProvider.parseListStatuses(Self.data("""
        {"data": {"repository": {"pullRequests": {"nodes": [
          {"number": 7, "isDraft": false, "mergeable": "MERGEABLE", "mergeStateStatus": "CLEAN",
           "reviewDecision": "APPROVED",
           "commits": {"nodes": [{"commit": {"statusCheckRollup": {"state": "SUCCESS"}}}]}},
          {"number": 8, "isDraft": false, "mergeable": "MERGEABLE", "mergeStateStatus": "BLOCKED",
           "reviewDecision": "REVIEW_REQUIRED", "commits": {"nodes": [{"commit": {"statusCheckRollup": null}}]}},
          {"number": 9, "isDraft": false, "mergeable": "MERGEABLE", "mergeStateStatus": "BLOCKED",
           "reviewDecision": null,
           "commits": {"nodes": [{"commit": {"statusCheckRollup": {"state": "FAILURE"}}}]}},
          {"number": 10, "isDraft": true, "mergeable": "MERGEABLE", "mergeStateStatus": "DRAFT",
           "reviewDecision": null, "commits": {"nodes": []}},
          null
        ]}}}}
        """))
        #expect(statuses.mapValues(\.kind) == [7: .ready, 8: .needsApproval, 9: .failing])
        #expect(statuses[7]?.hostCode == "CLEAN")
    }

    @Test("GitHub GraphQL: an answer with only errors is no verdicts; one that isn't JSON is a decoding error")
    func gitHubStatusesErrors() throws {
        let errorsOnly = try GitHubPullRequestProvider.parseListStatuses(Self.data("""
        {"data": null, "errors": [{"message": "Field 'mergeStateStatus' doesn't exist"}]}
        """))
        #expect(errorsOnly.isEmpty)
        let noRepo = try GitHubPullRequestProvider.parseListStatuses(Self.data(#"{"data": {"repository": null}}"#))
        #expect(noRepo.isEmpty)
        #expect(throws: PullRequestFetchError.self) {
            try GitHubPullRequestProvider.parseListStatuses(Self.data("not json"))
        }
    }

    @Test("GitHub: verdicts go only to open pull requests the read named")
    func applying() {
        func pull(_ number: Int, _ state: PullRequest.State) -> PullRequest {
            PullRequest(id: "\(number)", number: number, title: "T", state: state, authorLogin: nil,
                        authorAvatarURL: nil, sourceBranch: "f", targetBranch: "main", webURL: nil,
                        createdAt: nil, updatedAt: nil)
        }
        let statuses: [Int: PullListStatus] = [1: PullListStatus(kind: .ready), 2: PullListStatus(kind: .blocked),
                                               3: PullListStatus(kind: .running)]
        let out = GitHubPullRequestProvider.applying(statuses, to: [pull(1, .open), pull(2, .draft), pull(4, .open)])
        #expect(out.map(\.listStatus?.kind) == [.ready, nil, nil])
        #expect(out.map(\.number) == [1, 2, 4])
    }

    @Test("GitHub GraphQL endpoint: api.github.com, a GitHub Enterprise server, a custom API base")
    func graphQLURL() {
        let dotCom = RemoteHost(provider: .github, host: "github.com", owner: "o", repo: "r")
        #expect(GitHubPullRequestProvider.graphQLURL(for: dotCom)?.absoluteString == "https://api.github.com/graphql")
        let enterprise = RemoteHost(provider: .github, host: "ghe.example.test", owner: "o", repo: "r")
        #expect(GitHubPullRequestProvider.graphQLURL(for: enterprise)?.absoluteString
            == "https://ghe.example.test/api/graphql")
        var custom = RemoteHost(provider: .github, host: "ghe.example.test", owner: "o", repo: "r")
        custom.apiBaseURL = URL(string: "https://ghe.example.test/api/v3/")
        #expect(GitHubPullRequestProvider.graphQLURL(for: custom)?.absoluteString == "https://ghe.example.test/api/graphql")
        var proxied = RemoteHost(provider: .github, host: "github.com", owner: "o", repo: "r")
        proxied.apiBaseURL = URL(string: "https://proxy.example.test/github")
        #expect(GitHubPullRequestProvider.graphQLURL(for: proxied)?.absoluteString
            == "https://proxy.example.test/github/graphql")
    }

    @Test("GitHub GraphQL query asks for the fields the verdict needs")
    func query() {
        for field in ["mergeable", "mergeStateStatus", "reviewDecision", "statusCheckRollup", "isDraft", "states: OPEN"] {
            #expect(GitHubPullRequestProvider.listStatusQuery.contains(field))
        }
    }
}
