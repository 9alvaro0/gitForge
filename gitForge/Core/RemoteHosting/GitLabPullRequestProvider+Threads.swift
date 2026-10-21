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

    private func fetchDiscussions(host: RemoteHost, number: Int, page: Int, token: String) async throws -> [GitLabDiscussionDTO] {
        let data = try await RemoteAPI.send(Self.discussionsRequest(host: host, number: number, page: page, token: token),
                                            session: session)
        return try Self.decodeDiscussions(data)
    }

    // MARK: Requests

    nonisolated static func discussionsRequest(host: RemoteHost, number: Int, page: Int, token: String) -> URLRequest {
        var components = URLComponents(string: "\(base(for: host))/projects/\(encodeSlug(host))/merge_requests/\(number)/discussions")
        components?.queryItems = [URLQueryItem(name: "per_page", value: "100"), URLQueryItem(name: "page", value: "\(page)")]
        return makeRequest(url: components?.url, token: token)
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

    /// Discussions opened by a text `DiffNote`; their comments are the notes
    /// people wrote (GitLab threads "changed this line" system notes in).
    nonisolated fileprivate static func threads(from discussions: [GitLabDiscussionDTO], currentHead: String?) -> [ReviewThread] {
        discussions.compactMap { discussion in
            guard let first = discussion.notes.first, first.type == "DiffNote", first.system != true,
                  let position = first.position, position.position_type == "text" else { return nil }
            let ref = position.new_line.map { DiffLineRef(side: .new, line: $0) }
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
                                ref: ref, originalLine: position.new_line ?? position.old_line,
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
