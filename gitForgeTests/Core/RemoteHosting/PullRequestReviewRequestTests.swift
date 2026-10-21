import Foundation
import Testing
@testable import gitForge

@Suite("Review requests")
struct PullRequestReviewRequestTests {
    static let github = RemoteHost(provider: .github, host: "github.com", owner: "octo", repo: "app")

    private static func json(_ request: URLRequest) throws -> [String: String] {
        try #require(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String])
    }

    @Test("GitHub approve: POST /reviews with the head commit and no empty body")
    func gitHubApprove() throws {
        let request = GitHubPullRequestProvider.reviewRequest(host: Self.github, number: 7, verdict: .approve,
                                                              body: "  ", commitId: "abc123", token: "t")
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.github.com/repos/octo/app/pulls/7/reviews")
        #expect(try Self.json(request) == ["event": "APPROVE", "commit_id": "abc123"])
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t")
    }

    @Test("GitHub request changes carries the body")
    func gitHubRequestChanges() throws {
        let request = GitHubPullRequestProvider.reviewRequest(host: Self.github, number: 7, verdict: .requestChanges,
                                                              body: "Please add tests", commitId: nil, token: "t")
        #expect(try Self.json(request) == ["event": "REQUEST_CHANGES", "body": "Please add tests"])
    }
}
