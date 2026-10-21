import Foundation
import Testing
@testable import gitForge

@Suite("Review threads — requests")
struct ReviewThreadRequestTests {
    static let github = RemoteHost(provider: .github, host: "github.com", owner: "octo", repo: "app")
    static let gitlab = RemoteHost(provider: .gitlab, host: "gitlab.example.test", owner: "group", repo: "app",
                                   apiBaseURL: URL(string: "https://gitlab.example.test/api/v4"))
    static let refs = DiffRefs(baseSha: "base", startSha: "start", headSha: "head2")

    private static func json(_ request: URLRequest) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
    }

    private static func line(_ kind: DiffLine.Kind, old: Int?, new: Int?) -> DiffLine {
        DiffLine(id: 0, kind: kind, content: "x", oldLineNumber: old, newLineNumber: new)
    }

    @Test("GitHub line comment: side and line from the target")
    func gitHubComment() throws {
        let target = try #require(CommentTarget.make(path: "Sources/Retry.swift", oldPath: nil,
                                                     line: Self.line(.removed, old: 11, new: nil), side: .old))
        let request = GitHubPullRequestProvider.commentRequest(host: Self.github, number: 7, commitId: "abc", target: target,
                                                               body: "Why?", token: "t")
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.github.com/repos/octo/app/pulls/7/comments")
        let body = try Self.json(request)
        #expect(body["body"] as? String == "Why?")
        #expect(body["commit_id"] as? String == "abc")
        #expect(body["path"] as? String == "Sources/Retry.swift")
        #expect(body["line"] as? Int == 11)
        #expect(body["side"] as? String == "LEFT")
        #expect(body.count == 5)

        let added = try #require(CommentTarget.make(path: "a", oldPath: nil, line: Self.line(.added, old: nil, new: 12), side: .new))
        let right = try Self.json(GitHubPullRequestProvider.commentRequest(host: Self.github, number: 7, commitId: "abc",
                                                                            target: added, body: "x", token: "t"))
        #expect(right["line"] as? Int == 12 && right["side"] as? String == "RIGHT")
    }

    @Test("GitHub reply and resolve")
    func gitHubReplyAndResolve() throws {
        let reply = GitHubPullRequestProvider.replyRequest(host: Self.github, number: 7, commentId: "1001", body: "Done", token: "t")
        #expect(reply.httpMethod == "POST")
        #expect(reply.url?.path == "/repos/octo/app/pulls/7/comments/1001/replies")
        #expect(try Self.json(reply) as? [String: String] == ["body": "Done"])

        let resolve = GitHubPullRequestProvider.resolveRequest(host: Self.github, threadId: "PRRT_x", resolved: true, token: "t")
        #expect(resolve.url?.absoluteString == "https://api.github.com/graphql")
        let body = try Self.json(resolve)
        let query = try #require(body["query"] as? String)
        #expect(query.contains("resolveReviewThread") && !query.contains("unresolveReviewThread"))
        #expect(body["variables"] as? [String: String] == ["id": "PRRT_x"])

        let unresolve = GitHubPullRequestProvider.resolveRequest(host: Self.github, threadId: "PRRT_x", resolved: false, token: "t")
        #expect((try Self.json(unresolve)["query"] as? String)?.contains("unresolveReviewThread") == true)
    }

    struct PositionCase: Sendable, CustomTestStringConvertible {
        let kind: DiffLine.Kind
        let old: Int?
        let new: Int?
        let side: DiffSide
        var testDescription: String { "\(kind)" }
    }

    @Test("GitLab position per line kind", arguments: [
        PositionCase(kind: .context, old: 10, new: 10, side: .new),
        PositionCase(kind: .removed, old: 11, new: nil, side: .old),
        PositionCase(kind: .added, old: nil, new: 12, side: .new),
    ])
    func gitLabPosition(_ item: PositionCase) throws {
        let target = try #require(CommentTarget.make(path: "Sources/Retry.swift", oldPath: "Sources/Old.swift",
                                                     line: Self.line(item.kind, old: item.old, new: item.new), side: item.side))
        let request = GitLabPullRequestProvider.newDiscussionRequest(host: Self.gitlab, number: 9, refs: Self.refs, target: target,
                                                                     body: "Why?", token: "t")
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString
                == "https://gitlab.example.test/api/v4/projects/group%2Fapp/merge_requests/9/discussions")
        let body = try Self.json(request)
        #expect(body["body"] as? String == "Why?")
        let position = try #require(body["position"] as? [String: Any])
        #expect(position["position_type"] as? String == "text")
        #expect(position["base_sha"] as? String == "base")
        #expect(position["start_sha"] as? String == "start")
        #expect(position["head_sha"] as? String == "head2")
        #expect(position["old_path"] as? String == "Sources/Old.swift")
        #expect(position["new_path"] as? String == "Sources/Retry.swift")
        #expect(position["old_line"] as? Int == item.old)
        #expect(position["new_line"] as? Int == item.new)
        #expect((position["old_line"] == nil) == (item.old == nil))
        #expect((position["new_line"] == nil) == (item.new == nil))
    }

    @Test("GitLab: a file that wasn't renamed sends its path on both sides")
    func gitLabPlainPath() throws {
        let target = try #require(CommentTarget.make(path: "a.swift", oldPath: nil, line: Self.line(.added, old: nil, new: 3), side: .new))
        let position = try #require(try Self.json(GitLabPullRequestProvider.newDiscussionRequest(
            host: Self.gitlab, number: 9, refs: Self.refs, target: target, body: "x", token: "t"))["position"] as? [String: Any])
        #expect(position["old_path"] as? String == "a.swift" && position["new_path"] as? String == "a.swift")
    }

    @Test("GitLab reply and resolve")
    func gitLabReplyAndResolve() throws {
        let reply = GitLabPullRequestProvider.discussionReplyRequest(host: Self.gitlab, number: 9, discussionId: "d1",
                                                                     body: "Done", token: "t")
        #expect(reply.httpMethod == "POST")
        #expect(reply.url?.path == "/api/v4/projects/group%2Fapp/merge_requests/9/discussions/d1/notes"
                || reply.url?.path == "/api/v4/projects/group/app/merge_requests/9/discussions/d1/notes")
        #expect(try Self.json(reply) as? [String: String] == ["body": "Done"])

        let resolve = GitLabPullRequestProvider.resolveDiscussionRequest(host: Self.gitlab, number: 9, discussionId: "d1",
                                                                         resolved: true, token: "t")
        #expect(resolve.httpMethod == "PUT")
        #expect(resolve.url?.absoluteString.hasSuffix("/merge_requests/9/discussions/d1?resolved=true") == true)
        let reopen = GitLabPullRequestProvider.resolveDiscussionRequest(host: Self.gitlab, number: 9, discussionId: "d1",
                                                                        resolved: false, token: "t")
        #expect(reopen.url?.query == "resolved=false")
    }
}

/// The thread writes against a stub server: refusals, gone threads and
/// what's needed before anything is sent.
@Suite("Review threads — write flows")
@MainActor
struct ReviewThreadWriteFlowTests {
    static let pull = PullRequest(id: "9", number: 9, title: "T", state: .open, authorLogin: "marta", authorAvatarURL: nil,
                                  sourceBranch: "f", targetBranch: "main", webURL: nil, createdAt: nil, updatedAt: nil,
                                  headSha: "head2")

    static func thread(_ id: String, replyTo: String? = nil) -> ReviewThread {
        ReviewThread(id: id, path: "a.swift", oldPath: nil, ref: DiffLineRef(side: .new, line: 3), originalLine: 3,
                     isResolved: false, isOutdated: false, resolvedBy: nil, comments: [], canReply: true, canResolve: true,
                     canUnresolve: false, replyToCommentId: replyTo)
    }

    static let target = CommentTarget.make(path: "a.swift", oldPath: nil,
                                           line: DiffLine(id: 0, kind: .added, content: "x", oldLineNumber: nil, newLineNumber: 3),
                                           side: .new)!

    private static func gitLab() -> (StubServer, GitLabPullRequestProvider, RemoteHost) {
        let server = StubServer()
        let host = RemoteHost(provider: .gitlab, host: server.host, owner: "group", repo: "app",
                              apiBaseURL: URL(string: "https://\(server.host)/api/v4"))
        return (server, GitLabPullRequestProvider(session: server.http.session), host)
    }

    private static func gitHub() -> (StubServer, GitHubPullRequestProvider, RemoteHost) {
        let server = StubServer()
        let host = RemoteHost(provider: .github, host: server.host, owner: "octo", repo: "app",
                              apiBaseURL: URL(string: "https://\(server.host)/api/v3"))
        return (server, GitHubPullRequestProvider(session: server.http.session), host)
    }

    static let discussions = "/api/v4/projects/group/app/merge_requests/9/discussions"

    @Test("GitLab: a refused comment (its 401) with a working token reads as not allowed")
    func gitLabRefused() async {
        let (server, provider, host) = Self.gitLab()
        server.on("POST", "\(Self.discussions)/d1/notes", status: 401, body: Data(#"{"message":"401 Unauthorized"}"#.utf8))
        server.on("GET", "/api/v4/user", fixture: "gitlab-user")
        await #expect(throws: PullRequestActionError.forbidden) {
            try await provider.reply(host: host, pull: Self.pull, thread: Self.thread("d1"), body: "Done", token: "t")
        }
        server.on("PUT", "\(Self.discussions)/d1", status: 401, body: Data("{}".utf8))
        await #expect(throws: PullRequestActionError.forbidden) {
            try await provider.setResolved(true, host: host, pull: Self.pull, thread: Self.thread("d1"), token: "t")
        }
    }

    @Test("GitLab: a 401 with a dead token stays a 401, so the token gets refreshed")
    func gitLabDeadToken() async {
        let (server, provider, host) = Self.gitLab()
        server.on("POST", Self.discussions, status: 401, body: Data("{}".utf8))
        server.on("GET", "/api/v4/user", status: 401, body: Data("{}".utf8))
        var detail = PullRequestDetail(pull: Self.pull, descriptionMarkdown: nil, labels: [], reviewers: [], assignees: [],
                                       mergeable: nil, ciStatus: nil)
        detail.diffRefs = DiffRefs(baseSha: "base", startSha: "start", headSha: "head2")
        await #expect(throws: PullRequestFetchError.unauthorized) {
            try await provider.addComment(host: host, pull: Self.pull, detail: detail, target: Self.target, body: "x", token: "t")
        }
    }

    @Test("GitLab: without the detail's diff refs nothing is sent, and the error says the detail didn't load")
    func gitLabNoRefs() async {
        let (server, provider, host) = Self.gitLab()
        await #expect(throws: PullRequestActionError.other("The merge request's details didn't load. Refresh and try again.")) {
            try await provider.addComment(host: host, pull: Self.pull, detail: nil, target: Self.target, body: "x", token: "t")
        }
        #expect(server.requests.isEmpty)
    }

    @Test("GitHub: no head commit, nothing sent; a comment pins the head shown")
    func gitHubHead() async throws {
        let (server, provider, host) = Self.gitHub()
        var headless = Self.pull
        headless.headSha = nil
        await #expect(throws: PullRequestActionError.headChanged) {
            try await provider.addComment(host: host, pull: headless, detail: nil, target: Self.target, body: "x", token: "t")
        }
        #expect(server.requests.isEmpty)
        server.on("POST", "/api/v3/repos/octo/app/pulls/9/comments", status: 201, body: Data("{}".utf8))
        try await provider.addComment(host: host, pull: Self.pull, detail: nil, target: Self.target, body: "x", token: "t")
        #expect(server.requests.first?.json?["commit_id"] as? String == "head2")
    }

    @Test("GitHub: a thread without a comment to answer can't be replied to")
    func gitHubNoReplyTarget() async {
        let (server, provider, host) = Self.gitHub()
        await #expect(throws: PullRequestActionError.changedOnHost) {
            try await provider.reply(host: host, pull: Self.pull, thread: Self.thread("PRRT_x"), body: "x", token: "t")
        }
        #expect(server.requests.isEmpty)
    }

    @Test("GitHub: resolving a thread that's gone reads as changed; other GraphQL errors as refused")
    func gitHubResolveErrors() async {
        let (server, provider, host) = Self.gitHub()
        server.on("POST", "/api/graphql", body: Data(#"""
        {"data":{"resolveReviewThread":null},"errors":[{"type":"NOT_FOUND","message":"Could not resolve to a node with the global id of 'PRRT_x'"}]}
        """#.utf8))
        await #expect(throws: PullRequestActionError.changedOnHost) {
            try await provider.setResolved(true, host: host, pull: Self.pull, thread: Self.thread("PRRT_x"), token: "t")
        }
        let (other, otherProvider, otherHost) = Self.gitHub()
        other.on("POST", "/api/graphql", body: Data(#"{"data":null,"errors":[{"message":"Resource not accessible by integration"}]}"#.utf8))
        await #expect(throws: PullRequestActionError.rejected("Resource not accessible by integration")) {
            try await otherProvider.setResolved(true, host: otherHost, pull: Self.pull, thread: Self.thread("PRRT_x"), token: "t")
        }
    }

    @Test("GitHub: resolving without permission (GraphQL FORBIDDEN) reads as not allowed")
    func gitHubResolveForbidden() async {
        let (server, provider, host) = Self.gitHub()
        server.on("POST", "/api/graphql", body: Data(#"""
        {"data":{"resolveReviewThread":null},"errors":[{"type":"FORBIDDEN","path":["resolveReviewThread"],"message":"marta does not have the correct permissions to execute `ResolveReviewThread`"}]}
        """#.utf8))
        let error = await #expect(throws: (any Error).self) {
            try await provider.setResolved(true, host: host, pull: Self.pull, thread: Self.thread("PRRT_x"), token: "t")
        }
        #expect(error.map(PullRequestActionError.from) == .forbidden)
    }
}
