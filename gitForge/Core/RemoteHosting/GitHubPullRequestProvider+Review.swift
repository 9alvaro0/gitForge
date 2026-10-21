import Foundation

/// Reviews on GitHub: one `POST /reviews` carries the verdict and the comment.
/// API reference: https://docs.github.com/en/rest/pulls/reviews
extension GitHubPullRequestProvider: PullRequestReviewProvider {
    func requestChangesSupport(host: RemoteHost, token: String) async -> RequestChangesSupport {
        .supported
    }

    func submitReview(host: RemoteHost, pull: PullRequest, verdict: ReviewVerdict,
                      body: String, token: String) async throws -> String? {
        let request = Self.reviewRequest(host: host, number: pull.number, verdict: verdict, body: body,
                                         commitId: pull.headSha, token: token)
        _ = try await RemoteAPI.send(request)
        return nil
    }

    /// `commitId` pins the review to the head the user saw.
    nonisolated static func reviewRequest(host: RemoteHost, number: Int, verdict: ReviewVerdict, body: String,
                                          commitId: String?, token: String) -> URLRequest {
        var payload = ["event": verdict == .approve ? "APPROVE" : "REQUEST_CHANGES"]
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { payload["body"] = trimmed }
        if let commitId { payload["commit_id"] = commitId }
        let url = URL(string: "\(base(for: host))/repos/\(host.slug)/pulls/\(number)/reviews")
        return RemoteAPI.withJSON(makeRequest(url: url, token: token), method: "POST", body: payload)
    }
}
