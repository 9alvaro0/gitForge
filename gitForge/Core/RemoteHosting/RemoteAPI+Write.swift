import Foundation

// MARK: - Write requests

extension RemoteAPI {
    /// `request` with `method` and `body` as JSON (keys as written).
    nonisolated static func withJSON<Body: Encodable>(_ request: URLRequest, method: String, body: Body) -> URLRequest {
        var request = request
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(body)
        return request
    }

    /// A GraphQL POST to `endpoint` carrying `base`'s headers (auth, agent).
    nonisolated static func graphQL<Variables: Encodable>(_ base: URLRequest, endpoint: URL,
                                                          query: String, variables: Variables) -> URLRequest {
        var request = base
        request.url = endpoint
        return withJSON(request, method: "POST", body: GraphQLBody(query: query, variables: variables))
    }

    /// The `data` of a GraphQL answer. GraphQL reports failures with a 200
    /// and an `errors` list: GitHub's `FORBIDDEN` type is a refusal like a
    /// 403; otherwise the first message becomes the error.
    nonisolated static func decodeGraphQL<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        let envelope: GraphQLEnvelope<T>
        do {
            envelope = try JSONDecoder().decode(GraphQLEnvelope<T>.self, from: data)
        } catch {
            throw PullRequestFetchError.decoding(error.localizedDescription)
        }
        if let first = envelope.errors?.first {
            if first.type == "FORBIDDEN" { throw PullRequestFetchError.forbidden }
            throw PullRequestFetchError.server(200, first.message)
        }
        guard let value = envelope.data else {
            throw PullRequestFetchError.decoding("GraphQL answer without data")
        }
        return value
    }
}

// MARK: - Paging and timestamps

extension RemoteAPI {
    /// Pages 1, 2… of a list, until one comes back short of `pageSize` or
    /// `maxPages` were read.
    nonisolated static func collectPages<T: Sendable>(pageSize: Int, maxPages: Int,
                                                      _ fetch: @Sendable (Int) async throws -> [T]) async throws -> [T] {
        var all: [T] = []
        for page in 1...max(maxPages, 1) {
            let items = try await fetch(page)
            all += items
            if items.count < pageSize { break }
        }
        return all
    }

    /// An ISO-8601 timestamp, with or without fractional seconds, off the
    /// main actor (`parseDate`'s formatter lives on it).
    nonisolated static func parseTimestamp(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        return (try? Date(raw, strategy: .iso8601))
            ?? (try? Date(raw, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
    }
}

nonisolated private struct GraphQLBody<Variables: Encodable>: Encodable {
    let query: String
    let variables: Variables
}

nonisolated private struct GraphQLEnvelope<T: Decodable>: Decodable {
    let data: T?
    let errors: [Message]?

    struct Message: Decodable {
        let message: String
        let type: String?
    }
}
