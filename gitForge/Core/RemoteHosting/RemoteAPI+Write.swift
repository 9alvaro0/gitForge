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
    /// and an `errors` list: the first message becomes the error.
    nonisolated static func decodeGraphQL<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        let envelope: GraphQLEnvelope<T>
        do {
            envelope = try JSONDecoder().decode(GraphQLEnvelope<T>.self, from: data)
        } catch {
            throw PullRequestFetchError.decoding(error.localizedDescription)
        }
        if let first = envelope.errors?.first {
            throw PullRequestFetchError.server(200, first.message)
        }
        guard let value = envelope.data else {
            throw PullRequestFetchError.decoding("GraphQL answer without data")
        }
        return value
    }
}

nonisolated private struct GraphQLBody<Variables: Encodable>: Encodable {
    let query: String
    let variables: Variables
}

nonisolated private struct GraphQLEnvelope<T: Decodable>: Decodable {
    let data: T?
    let errors: [Message]?

    struct Message: Decodable { let message: String }
}
