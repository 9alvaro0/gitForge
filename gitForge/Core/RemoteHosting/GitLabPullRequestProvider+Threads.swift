import Foundation

/// Diff discussions on GitLab, as review threads.
/// API reference: https://docs.gitlab.com/api/discussions/#merge-requests
extension GitLabPullRequestProvider {
    /// 100 discussions a page, at most 50 pages. The pages count every
    /// discussion: general ones and system notes take room too.
    func fetchThreads(host: RemoteHost, pull: PullRequest, detail: PullRequestDetail?, token: String) async throws -> [ReviewThread] {
        let discussions = try await RemoteAPI.collectPages(pageSize: 100, maxPages: 50) { page in
            try await fetchDiscussions(host: host, number: pull.number, page: page, token: token)
        }
        return Self.threads(from: discussions, currentHead: detail?.diffRefs?.headSha)
    }

    /// A new discussion positioned against the MR's current `diff_refs`.
    func addComment(host: RemoteHost, pull: PullRequest, detail: PullRequestDetail?, target: CommentTarget,
                    body: String, token: String) async throws {
        guard let refs = detail?.diffRefs else { throw PullRequestActionError.headChanged }
        try await sendWrite(Self.newDiscussionRequest(host: host, number: pull.number, refs: refs, target: target,
                                                      body: body, token: token), host: host, token: token)
    }

    func reply(host: RemoteHost, pull: PullRequest, thread: ReviewThread, body: String, token: String) async throws {
        try await sendWrite(Self.discussionReplyRequest(host: host, number: pull.number, discussionId: thread.id,
                                                        body: body, token: token), host: host, token: token)
    }

    func setResolved(_ resolved: Bool, host: RemoteHost, pull: PullRequest, thread: ReviewThread, token: String) async throws {
        try await sendWrite(Self.resolveDiscussionRequest(host: host, number: pull.number, discussionId: thread.id,
                                                          resolved: resolved, token: token), host: host, token: token)
    }

    /// GitLab answers 401 when it refuses a write, unless the token itself
    /// is dead: then `/user` throws the 401 on and the store refreshes the token.
    private func sendWrite(_ request: URLRequest, host: RemoteHost, token: String) async throws {
        do {
            _ = try await RemoteAPI.send(request, session: session)
        } catch PullRequestFetchError.unauthorized {
            _ = try await RemoteAPI.send(Self.makeRequest(url: URL(string: "\(Self.base(for: host))/user"), token: token),
                                         session: session)
            throw PullRequestActionError.forbidden
        }
    }

    private func fetchDiscussions(host: RemoteHost, number: Int, page: Int, token: String) async throws -> [GitLabDiscussionDTO] {
        let data = try await RemoteAPI.send(Self.discussionsRequest(host: host, number: number, page: page, token: token),
                                            session: session)
        return try Self.decodeDiscussions(data)
    }

    // MARK: Requests

    nonisolated static func discussionsRequest(host: RemoteHost, number: Int, page: Int, token: String) -> URLRequest {
        var components = URLComponents(string: discussionsPath(host, number))
        components?.queryItems = [URLQueryItem(name: "per_page", value: "100"), URLQueryItem(name: "page", value: "\(page)")]
        return makeRequest(url: components?.url, token: token)
    }

    /// `old_line` and `new_line` carry the target's numbers that exist:
    /// both on a context line, one on an added or removed line.
    nonisolated static func newDiscussionRequest(host: RemoteHost, number: Int, refs: DiffRefs, target: CommentTarget,
                                                 body: String, token: String) -> URLRequest {
        nonisolated struct Position: Encodable {
            let position_type = "text"
            let base_sha: String
            let start_sha: String
            let head_sha: String
            let old_path: String
            let new_path: String
            let old_line: Int?
            let new_line: Int?
        }
        nonisolated struct Body: Encodable {
            let body: String
            let position: Position
        }
        let position = Position(base_sha: refs.baseSha, start_sha: refs.startSha, head_sha: refs.headSha,
                                old_path: target.oldPath ?? target.path, new_path: target.path,
                                old_line: target.oldLine, new_line: target.newLine)
        return RemoteAPI.withJSON(makeRequest(url: URL(string: discussionsPath(host, number)), token: token), method: "POST",
                                  body: Body(body: body, position: position))
    }

    nonisolated static func discussionReplyRequest(host: RemoteHost, number: Int, discussionId: String, body: String,
                                                   token: String) -> URLRequest {
        RemoteAPI.withJSON(makeRequest(url: URL(string: "\(discussionsPath(host, number))/\(discussionId)/notes"), token: token),
                           method: "POST", body: ["body": body])
    }

    nonisolated static func resolveDiscussionRequest(host: RemoteHost, number: Int, discussionId: String, resolved: Bool,
                                                     token: String) -> URLRequest {
        makeRequest(url: URL(string: "\(discussionsPath(host, number))/\(discussionId)?resolved=\(resolved)"), token: token,
                    method: "PUT")
    }

    nonisolated private static func discussionsPath(_ host: RemoteHost, _ number: Int) -> String {
        "\(base(for: host))/projects/\(encodeSlug(host))/merge_requests/\(number)/discussions"
    }

    // MARK: Parsing

    /// The diff threads among `data`'s discussions. A thread left on an
    /// older head than `currentHead` is outdated; without a head, none is.
    nonisolated static func parseDiscussions(_ data: Data, currentHead: String?) throws -> [ReviewThread] {
        threads(from: try decodeDiscussions(data), currentHead: currentHead)
    }

    nonisolated private static func decodeDiscussions(_ data: Data) throws -> [GitLabDiscussionDTO] {
        do {
            return try JSONDecoder().decode([GitLabDiscussionDTO].self, from: data)
        } catch {
            throw PullRequestFetchError.decoding(error.localizedDescription)
        }
    }

    /// Discussions opened by a `DiffNote`; their comments are the notes
    /// people wrote (GitLab threads "changed this line" system notes in).
    /// File and image comments have no line: they go above their file.
    nonisolated fileprivate static func threads(from discussions: [GitLabDiscussionDTO], currentHead: String?) -> [ReviewThread] {
        discussions.compactMap { discussion in
            guard let first = discussion.notes.first, first.type == "DiffNote", first.system != true,
                  let position = first.position,
                  ["text", "file", "image"].contains(position.position_type) else { return nil }
            let onLine = position.position_type == "text"
            let ref = !onLine ? nil : position.new_line.map { DiffLineRef(side: .new, line: $0) }
                ?? position.old_line.map { DiffLineRef(side: .old, line: $0) }
            let path = position.new_path ?? position.old_path ?? ""
            let comments = discussion.notes.filter { $0.system != true }.map { note in
                ReviewComment(id: String(note.id), authorLogin: note.author?.username,
                              authorAvatarURL: note.author?.avatar_url.flatMap(URL.init(string:)),
                              body: note.body ?? "", createdAt: RemoteAPI.parseTimestamp(note.created_at))
            }
            let resolvable = first.resolvable ?? false
            return ReviewThread(id: discussion.id, path: path,
                                oldPath: position.old_path.flatMap { $0 == path ? nil : $0 },
                                ref: ref, originalLine: onLine ? position.new_line ?? position.old_line : nil,
                                isResolved: first.resolved ?? false,
                                isOutdated: currentHead.map { position.head_sha != $0 } ?? false,
                                resolvedBy: first.resolved_by?.username, comments: comments,
                                canReply: true, canResolve: resolvable, canUnresolve: resolvable, replyToCommentId: nil)
        }
    }
}

nonisolated private struct GitLabDiscussionDTO: Decodable, Sendable {
    let id: String
    let notes: [Note]

    struct Note: Decodable, Sendable {
        let id: Int
        let type: String?
        let body: String?
        let system: Bool?
        let resolvable: Bool?
        let resolved: Bool?
        let resolved_by: User?
        let created_at: String?
        let author: User?
        let position: Position?
    }
    struct User: Decodable, Sendable {
        let username: String?
        let avatar_url: String?
    }
    struct Position: Decodable, Sendable {
        let head_sha: String?
        let position_type: String?
        let old_path: String?
        let new_path: String?
        let old_line: Int?
        let new_line: Int?
    }
}
