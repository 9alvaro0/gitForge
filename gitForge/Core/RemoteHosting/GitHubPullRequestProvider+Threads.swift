import Foundation

/// Review threads on GitHub. Reading them is GraphQL: the REST comments
/// don't say whether a thread is resolved.
/// API reference: https://docs.github.com/en/graphql/reference/objects#pullrequestreviewthread
extension GitHubPullRequestProvider {
    /// 100 threads a page, at most 30 pages.
    func fetchThreads(host: RemoteHost, pull: PullRequest, detail: PullRequestDetail?, token: String) async throws -> [ReviewThread] {
        var threads: [ReviewThread] = []
        var cursor: String?
        for _ in 0..<Self.threadPagesCap {
            let data = try await RemoteAPI.send(Self.threadsRequest(host: host, number: pull.number, after: cursor, token: token),
                                                session: session)
            let page = try Self.parseThreads(data)
            threads += page.threads
            guard let next = page.nextCursor else { break }
            cursor = next
        }
        return threads
    }

    nonisolated static let threadPagesCap = 30

    // MARK: Requests

    /// `https://api.github.com/graphql` on github.com; next to the REST base
    /// (`…/api/v3` → `…/api/graphql`) on Enterprise Server.
    nonisolated static func graphQLEndpoint(for host: RemoteHost) -> URL {
        var base = base(for: host)
        if base == "https://api.github.com" { return URL(string: "https://api.github.com/graphql")! }
        if base.hasSuffix("/api/v3") {
            base.removeLast("/api/v3".count)
            if let url = URL(string: "\(base)/api/graphql") { return url }
        }
        return URL(string: "https://\(host.host)/api/graphql") ?? URL(string: "https://api.github.com/graphql")!
    }

    /// At most 100 comments a thread: longer threads show their first 100.
    nonisolated static let threadsQuery = """
    query($owner: String!, $name: String!, $number: Int!, $after: String) {
      repository(owner: $owner, name: $name) { pullRequest(number: $number) {
        reviewThreads(first: 100, after: $after) {
          pageInfo { hasNextPage endCursor }
          nodes { id isResolved isOutdated path line originalLine diffSide
                  viewerCanResolve viewerCanUnresolve viewerCanReply resolvedBy { login }
                  comments(first: 100) { nodes { databaseId body createdAt author { login avatarUrl } } } } } } }
    }
    """

    nonisolated static func threadsRequest(host: RemoteHost, number: Int, after: String?, token: String) -> URLRequest {
        nonisolated struct Variables: Encodable {
            let owner: String
            let name: String
            let number: Int
            let after: String?
        }
        return RemoteAPI.graphQL(makeRequest(url: nil, token: token), endpoint: graphQLEndpoint(for: host), query: threadsQuery,
                                 variables: Variables(owner: host.owner, name: host.repo, number: number, after: after))
    }

    // MARK: Parsing

    /// One page of threads, and the cursor of the next when there is one.
    nonisolated static func parseThreads(_ data: Data) throws -> (threads: [ReviewThread], nextCursor: String?) {
        let answer = try RemoteAPI.decodeGraphQL(data, as: ThreadsAnswer.self)
        guard let page = answer.repository?.pullRequest?.reviewThreads else { return ([], nil) }
        let threads = page.nodes.compactMap { $0 }.map { node in
            let comments = (node.comments?.nodes ?? []).compactMap { $0 }.enumerated().map { index, comment in
                ReviewComment(id: comment.databaseId.map(String.init) ?? "\(node.id)-\(index)",
                              authorLogin: comment.author?.login,
                              authorAvatarURL: comment.author?.avatarUrl.flatMap(URL.init(string:)),
                              body: comment.body,
                              createdAt: RemoteAPI.parseTimestamp(comment.createdAt))
            }
            return ReviewThread(id: node.id, path: node.path, oldPath: nil,
                                ref: node.line.map { DiffLineRef(side: node.diffSide == "LEFT" ? .old : .new, line: $0) },
                                originalLine: node.originalLine, isResolved: node.isResolved, isOutdated: node.isOutdated,
                                resolvedBy: node.resolvedBy?.login, comments: comments,
                                canReply: node.viewerCanReply ?? false, canResolve: node.viewerCanResolve ?? false,
                                canUnresolve: node.viewerCanUnresolve ?? false,
                                replyToCommentId: node.comments?.nodes.compactMap { $0 }.first?.databaseId.map(String.init))
        }
        return (threads, page.pageInfo.hasNextPage ? page.pageInfo.endCursor : nil)
    }
}

nonisolated private struct ThreadsAnswer: Decodable {
    let repository: Repository?

    struct Repository: Decodable { let pullRequest: PullRequest? }
    struct PullRequest: Decodable { let reviewThreads: Page }
    struct Page: Decodable {
        let pageInfo: PageInfo
        let nodes: [Node?]
    }
    struct PageInfo: Decodable {
        let hasNextPage: Bool
        let endCursor: String?
    }
    struct Node: Decodable {
        let id: String
        let isResolved: Bool
        let isOutdated: Bool
        let path: String
        let line: Int?
        let originalLine: Int?
        let diffSide: String?
        let viewerCanResolve: Bool?
        let viewerCanUnresolve: Bool?
        let viewerCanReply: Bool?
        let resolvedBy: Login?
        let comments: Comments?
    }
    struct Login: Decodable { let login: String }
    struct Comments: Decodable { let nodes: [Comment?] }
    struct Comment: Decodable {
        let databaseId: Int?
        let body: String
        let createdAt: String?
        let author: Author?
    }
    struct Author: Decodable {
        let login: String
        let avatarUrl: String?
    }
}
