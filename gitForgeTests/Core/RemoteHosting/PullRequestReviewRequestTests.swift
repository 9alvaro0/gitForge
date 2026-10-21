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

    static let gitlab = RemoteHost(provider: .gitlab, host: "gitlab.example.test", owner: "group/sub", repo: "app",
                                   apiBaseURL: URL(string: "https://gitlab.example.test/api/v4"))

    @Test("GitLab approve pins the head SHA; notes carry the body")
    func gitLabApproveAndNote() throws {
        let approve = GitLabPullRequestProvider.approveRequest(host: Self.gitlab, number: 9, sha: "def456", token: "t")
        #expect(approve.httpMethod == "POST")
        #expect(approve.url?.absoluteString == "https://gitlab.example.test/api/v4/projects/group%2Fsub%2Fapp/merge_requests/9/approve")
        #expect(try Self.json(approve) == ["sha": "def456"])
        let note = GitLabPullRequestProvider.noteRequest(host: Self.gitlab, number: 9, body: "LGTM", token: "t")
        #expect(note.url?.path.hasSuffix("/merge_requests/9/notes") == true)
        #expect(try Self.json(note) == ["body": "LGTM"])
    }

    @Test("The request-changes note ends with the quick action")
    func quickAction() {
        #expect(GitLabPullRequestProvider.requestChangesNoteBody("  Add tests \n")
                == "Add tests\n\n/submit_review requested_changes")
    }

    @Test("Support: mutation or 17.3+ yes; older or unknown no, with the reason")
    func support() {
        let reason = "Requesting changes needs GitLab 17.3 or later"
        #expect(GitLabPullRequestProvider.requestChangesSupport(.init(version: .init(major: 17, minor: 3), hasRequestChangesMutation: false)) == .supported)
        #expect(GitLabPullRequestProvider.requestChangesSupport(.init(version: .init(major: 16, minor: 11), hasRequestChangesMutation: false)) == .unsupported(reason: reason))
        #expect(GitLabPullRequestProvider.requestChangesSupport(.unknown) == .unsupported(reason: reason))
        #expect(GitLabPullRequestProvider.requestChangesSupport(.init(version: nil, hasRequestChangesMutation: true)) == .supported)
    }

    @Test("GraphQL lives next to the REST base, and the probe finds the mutation")
    func graphQL() {
        #expect(GitLabPullRequestProvider.graphQLEndpoint(for: Self.gitlab).absoluteString == "https://gitlab.example.test/api/graphql")
        #expect(GitLabPullRequestProvider.parseHasRequestChangesMutation(Fixture.data("gitlab-graphql-mutations")))
        #expect(!GitLabPullRequestProvider.parseHasRequestChangesMutation(Data(#"{"data":{"__type":{"fields":[{"name":"mergeRequestAccept"}]}}}"#.utf8)))
        #expect(!GitLabPullRequestProvider.parseHasRequestChangesMutation(Data("not json".utf8)))
    }

    @Test("The mutation targets the project path and the MR iid")
    func mutationRequest() throws {
        let request = GitLabPullRequestProvider.requestChangesMutationRequest(host: Self.gitlab, number: 9, token: "t")
        #expect(request.url?.absoluteString == "https://gitlab.example.test/api/graphql")
        let json = try #require(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        #expect((json["query"] as? String)?.contains("mergeRequestRequestChanges") == true)
        #expect(json["variables"] as? [String: String] == ["projectPath": "group/sub/app", "iid": "9"])
    }

    @Test("The viewer's approval comes from /approvals")
    func viewerApproval() {
        #expect(GitLabPullRequestProvider.parseViewerApproval(Fixture.data("gitlab-approvals-viewer"))
                == ViewerApproval(canApprove: true, hasApproved: false))
        #expect(GitLabPullRequestProvider.parseViewerApproval(Data("{}".utf8)) == nil)
    }

    @Test("An unreadable /version means an unknown instance")
    func unreadableVersion() {
        #expect(GitLabPullRequestProvider.instanceInfo(version: nil, mutations: nil) == .unknown)
        #expect(GitLabPullRequestProvider.instanceInfo(version: Data("<html>".utf8), mutations: nil) == .unknown)
        #expect(GitLabPullRequestProvider.instanceInfo(version: Fixture.data("gitlab-version"),
                                                       mutations: Fixture.data("gitlab-graphql-mutations"))
                == GitLabInstanceInfo(version: .init(major: 17, minor: 5), hasRequestChangesMutation: true))
    }
}

/// The GitLab review flow against a stub server: what gets posted, in which
/// order, and what a failed comment turns into.
@Suite("GitLab review flow")
@MainActor
struct GitLabReviewFlowTests {
    private static func setUp() -> (StubServer, GitLabPullRequestProvider, RemoteHost, PullRequest) {
        let server = StubServer()
        let provider = GitLabPullRequestProvider(session: server.http.session)
        let host = RemoteHost(provider: .gitlab, host: server.host, owner: "group", repo: "app",
                              apiBaseURL: URL(string: "https://\(server.host)/api/v4"))
        let pull = PullRequest(id: "9", number: 9, title: "T", state: .open, authorLogin: "marta", authorAvatarURL: nil,
                               sourceBranch: "f", targetBranch: "main", webURL: nil, createdAt: nil, updatedAt: nil,
                               headSha: "def456")
        return (server, provider, host, pull)
    }

    static let mr = "/api/v4/projects/group/app/merge_requests/9"

    @Test("Approve posts the approval, then the comment")
    func approveThenNote() async throws {
        let (server, provider, host, pull) = Self.setUp()
        server.on("POST", "\(Self.mr)/approve", status: 201, body: Data("{}".utf8))
        server.on("POST", "\(Self.mr)/notes", status: 201, body: Data("{}".utf8))
        let warning = try await provider.submitReview(host: host, pull: pull, verdict: .approve, body: "LGTM", token: "t")
        #expect(warning == nil)
        #expect(server.requests.map { "\($0.method) \($0.path)" } == ["POST \(Self.mr)/approve", "POST \(Self.mr)/notes"])
    }

    @Test("Approve without a comment posts no note")
    func approveOnly() async throws {
        let (server, provider, host, pull) = Self.setUp()
        server.on("POST", "\(Self.mr)/approve", status: 201, body: Data("{}".utf8))
        _ = try await provider.submitReview(host: host, pull: pull, verdict: .approve, body: "  ", token: "t")
        #expect(server.requests("POST", "\(Self.mr)/notes").isEmpty)
    }

    @Test("The approval stands when its comment fails")
    func noteFails() async throws {
        let (server, provider, host, pull) = Self.setUp()
        server.on("POST", "\(Self.mr)/approve", status: 201, body: Data("{}".utf8))
        server.on("POST", "\(Self.mr)/notes", status: 500, body: Data("boom".utf8))
        let warning = try await provider.submitReview(host: host, pull: pull, verdict: .approve, body: "LGTM", token: "t")
        #expect(warning == "Approved, but the comment couldn't be posted: Server returned 500: boom")
    }

    @Test("A comment the host refuses after the verdict names the account", arguments: [403, 401])
    func noteRefused(status: Int) async throws {
        let (server, provider, host, pull) = Self.setUp()
        server.on("POST", "\(Self.mr)/approve", status: 201, body: Data("{}".utf8))
        server.on("POST", "\(Self.mr)/notes", status: status, body: Data(#"{"message":"Not allowed"}"#.utf8))
        server.on("GET", "/api/v4/user", fixture: "gitlab-user")
        let warning = try await provider.submitReview(host: host, pull: pull, verdict: .approve, body: "LGTM", token: "t")
        #expect(warning == "Approved, but the comment couldn't be posted: "
                + "Your account (tanuki-test on \(server.host)) can't comment on this merge request.")
    }

    @Test("A comment the host turns down shows its message, not its JSON")
    func noteInvalid() async throws {
        let (server, provider, host, pull) = Self.setUp()
        server.on("POST", "\(Self.mr)/approve", status: 201, body: Data("{}".utf8))
        server.on("POST", "\(Self.mr)/notes", status: 400,
                  body: Data(#"{"message":{"note":["is too long (maximum is 1000000 characters)"]}}"#.utf8))
        let warning = try await provider.submitReview(host: host, pull: pull, verdict: .approve, body: "LGTM", token: "t")
        #expect(warning == "Approved, but the comment couldn't be posted: "
                + "Server returned 400: is too long (maximum is 1000000 characters)")
    }

    @Test("A refused approval (GitLab's 401) with a working token reads as refused, not as a dead token")
    func approvalRefused() async {
        let (server, provider, host, pull) = Self.setUp()
        server.on("POST", "\(Self.mr)/approve", status: 401, body: Data(#"{"message":"401 Unauthorized"}"#.utf8))
        server.on("GET", "/api/v4/user", fixture: "gitlab-user")
        await #expect(throws: PullRequestActionError.rejected(GitLabPullRequestProvider.approvalRefusedReason)) {
            try await provider.submitReview(host: host, pull: pull, verdict: .approve, body: "LGTM", token: "t")
        }
        #expect(server.requests("POST", "\(Self.mr)/notes").isEmpty)
    }

    @Test("A 401 on approve with a dead token stays a 401, so the token gets refreshed")
    func approvalDeadToken() async {
        let (server, provider, host, pull) = Self.setUp()
        server.on("POST", "\(Self.mr)/approve", status: 401, body: Data("{}".utf8))
        server.on("GET", "/api/v4/user", status: 401, body: Data("{}".utf8))
        await #expect(throws: PullRequestFetchError.unauthorized) {
            try await provider.submitReview(host: host, pull: pull, verdict: .approve, body: "", token: "t")
        }
    }

    /// Version 17.5 and a schema with the mutation; the first two GraphQL
    /// answers are the probe's, then `mutation`.
    private static func withMutation(_ server: StubServer, mutation: String) {
        server.on("GET", "/api/v4/version", fixture: "gitlab-version")
        server.on("POST", "/api/graphql", fixture: "gitlab-graphql-mutations")
        server.on("POST", "/api/graphql", body: Data(mutation.utf8))
    }

    @Test("With the mutation: the mutation, then the comment as a plain note")
    func mutationThenNote() async throws {
        let (server, provider, host, pull) = Self.setUp()
        Self.withMutation(server, mutation: #"{"data":{"mergeRequestRequestChanges":{"errors":[]}}}"#)
        server.on("POST", "\(Self.mr)/notes", status: 201, body: Data("{}".utf8))
        let warning = try await provider.submitReview(host: host, pull: pull, verdict: .requestChanges, body: "Add tests", token: "t")
        #expect(warning == nil)
        let graphQL = server.requests("POST", "/api/graphql")
        #expect(graphQL.count == 2)
        #expect((graphQL.last?.json?["query"] as? String)?.contains("mergeRequestRequestChanges") == true)
        #expect(server.requests("POST", "\(Self.mr)/notes").map { $0.json?["body"] as? String } == ["Add tests"])
    }

    @Test("The mutation's errors refuse the review and post no note", arguments: [
        #"{"data":{"mergeRequestRequestChanges":{"errors":["You don't have permission"]}}}"#,
        #"{"errors":[{"message":"You don't have permission"}]}"#,
    ])
    func mutationRefused(answer: String) async {
        let (server, provider, host, pull) = Self.setUp()
        Self.withMutation(server, mutation: answer)
        await #expect(throws: PullRequestActionError.rejected("You don't have permission")) {
            try await provider.submitReview(host: host, pull: pull, verdict: .requestChanges, body: "Add tests", token: "t")
        }
        #expect(server.requests("POST", "\(Self.mr)/notes").isEmpty)
    }

    @Test("With the mutation, a failed comment is a warning")
    func mutationNoteFails() async throws {
        let (server, provider, host, pull) = Self.setUp()
        Self.withMutation(server, mutation: #"{"data":{"mergeRequestRequestChanges":{"errors":[]}}}"#)
        server.on("POST", "\(Self.mr)/notes", status: 500, body: Data("boom".utf8))
        let warning = try await provider.submitReview(host: host, pull: pull, verdict: .requestChanges, body: "Add tests", token: "t")
        #expect(warning == "Requested changes, but the comment couldn't be posted: Server returned 500: boom")
    }

    @Test("17.3+ without the mutation: one note with the quick action")
    func quickActionNote() async throws {
        let (server, provider, host, pull) = Self.setUp()
        server.on("GET", "/api/v4/version", fixture: "gitlab-version")
        server.on("POST", "/api/graphql", body: Data(#"{"data":{"__type":{"fields":[{"name":"mergeRequestAccept"}]}}}"#.utf8))
        server.on("POST", "\(Self.mr)/notes", status: 201, body: Data("{}".utf8))
        #expect(await provider.requestChangesSupport(host: host, token: "t") == .supported)
        _ = try await provider.submitReview(host: host, pull: pull, verdict: .requestChanges, body: "Add tests", token: "t")
        #expect(server.requests("POST", "\(Self.mr)/notes").map { $0.json?["body"] as? String }
                == ["Add tests\n\n/submit_review requested_changes"])
        #expect(server.requests("POST", "\(Self.mr)/approve").isEmpty)
    }

    @Test("Before 17.3 nothing is posted and the reason comes back")
    func oldInstance() async {
        let (server, provider, host, pull) = Self.setUp()
        server.on("GET", "/api/v4/version", fixture: "gitlab-version-old")
        let reason = "Requesting changes needs GitLab 17.3 or later"
        #expect(await provider.requestChangesSupport(host: host, token: "t") == .unsupported(reason: reason))
        await #expect(throws: PullRequestActionError.rejected(reason)) {
            try await provider.submitReview(host: host, pull: pull, verdict: .requestChanges, body: "Add tests", token: "t")
        }
        #expect(server.requests.filter { $0.method == "POST" }.isEmpty)
        #expect(server.requests("POST", "/api/graphql").isEmpty)
    }
}

