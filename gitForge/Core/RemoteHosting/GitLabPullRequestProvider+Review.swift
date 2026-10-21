import Foundation

/// Reviews on GitLab. The verdict and the comment are separate calls: the
/// verdict first, so a failed comment never leaves a comment without it.
/// "Request changes" depends on the instance (spec §6.3, §6.4): the GraphQL
/// mutation when the schema has it, else the `/submit_review` quick action
/// from 17.3, else not at all.
extension GitLabPullRequestProvider: PullRequestReviewProvider {
    func requestChangesSupport(host: RemoteHost, token: String) async -> RequestChangesSupport {
        Self.requestChangesSupport(await instanceInfo(host: host, token: token))
    }

    func submitReview(host: RemoteHost, pull: PullRequest, verdict: ReviewVerdict,
                      body: String, token: String) async throws -> String? {
        switch verdict {
        case .approve:
            do {
                _ = try await RemoteAPI.send(Self.approveRequest(host: host, number: pull.number, sha: pull.headSha, token: token),
                                             session: session)
            } catch PullRequestFetchError.unauthorized {
                // A refusal, unless the token itself is dead: then `/user`
                // throws the 401 on and the store refreshes the token.
                _ = try await RemoteAPI.send(Self.makeRequest(url: URL(string: "\(Self.base(for: host))/user"), token: token),
                                             session: session)
                throw PullRequestActionError.rejected(Self.approvalRefusedReason)
            }
            return await postComment(body, host: host, number: pull.number, token: token) {
                String(localized: "Approved, but the comment couldn't be posted: \($0)")
            }
        case .requestChanges:
            let info = await instanceInfo(host: host, token: token)
            if info.hasRequestChangesMutation {
                try await requestChangesByMutation(host: host, number: pull.number, token: token)
                return await postComment(body, host: host, number: pull.number, token: token) {
                    String(localized: "Requested changes, but the comment couldn't be posted: \($0)")
                }
            }
            guard let version = info.version, version >= .requestChanges else {
                throw PullRequestActionError.rejected(Self.requestChangesUnsupportedReason)
            }
            let note = Self.noteRequest(host: host, number: pull.number, body: Self.requestChangesNoteBody(body), token: token)
            _ = try await RemoteAPI.send(note, session: session)
            return nil
        }
    }

    // MARK: Steps

    /// Loaded once per host: `/version`, then the GraphQL probe only where
    /// the mutation can exist. Any failure reads as an older instance.
    private func instanceInfo(host: RemoteHost, token: String) async -> GitLabInstanceInfo {
        await GitLabInstanceInfoCache.shared.info(for: host.host) { [session] in
            let version = try? await RemoteAPI.send(Self.versionRequest(host: host, token: token), session: session)
            guard let parsed = version.flatMap(Self.parseVersion), parsed >= .requestChanges else {
                return Self.instanceInfo(version: version, mutations: nil)
            }
            let probe = RemoteAPI.graphQL(Self.makeRequest(url: nil, token: token), endpoint: Self.graphQLEndpoint(for: host),
                                          query: Self.requestChangesProbe, variables: [String: String]())
            let mutations = try? await RemoteAPI.send(probe, session: session)
            return Self.instanceInfo(version: version, mutations: mutations)
        }
    }

    private func requestChangesByMutation(host: RemoteHost, number: Int, token: String) async throws {
        let data = try await RemoteAPI.send(Self.requestChangesMutationRequest(host: host, number: number, token: token),
                                            session: session)
        nonisolated struct Payload: Decodable {
            let mergeRequestRequestChanges: Outcome?
            struct Outcome: Decodable { let errors: [String]? }
        }
        let payload: Payload
        do {
            payload = try RemoteAPI.decodeGraphQL(data, as: Payload.self)
        } catch PullRequestFetchError.server(200, let message) {
            throw PullRequestActionError.rejected(message)
        }
        if let errors = payload.mergeRequestRequestChanges?.errors, !errors.isEmpty {
            throw PullRequestActionError.rejected(errors.joined(separator: "; "))
        }
    }

    /// The comment after a verdict that already landed: a failure is a
    /// warning, never an error, so the verdict isn't retried.
    private func postComment(_ body: String, host: RemoteHost, number: Int, token: String,
                             warning: (String) -> String) async -> String? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            _ = try await RemoteAPI.send(Self.noteRequest(host: host, number: number, body: trimmed, token: token), session: session)
            return nil
        } catch {
            return warning((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    // MARK: Requests

    nonisolated static var requestChangesUnsupportedReason: String {
        String(localized: "Requesting changes needs GitLab 17.3 or later")
    }

    /// GitLab answers 401 when it refuses an approval: already approved,
    /// not eligible, or the project asks for the user's password.
    nonisolated static var approvalRefusedReason: String {
        String(localized: "the approval wasn't accepted. It may already be approved, or the project asks for your password to approve.")
    }

    nonisolated static let requestChangesProbe = #"query { __type(name: "Mutation") { fields { name } } }"#

    /// `…/api/v4` → `…/api/graphql`.
    nonisolated static func graphQLEndpoint(for host: RemoteHost) -> URL {
        var base = base(for: host)
        if base.hasSuffix("/api/v4") { base.removeLast("/api/v4".count) }
        return URL(string: "\(base)/api/graphql") ?? URL(string: "https://\(host.host)/api/graphql")!
    }

    nonisolated static func versionRequest(host: RemoteHost, token: String) -> URLRequest {
        makeRequest(url: URL(string: "\(base(for: host))/version"), token: token)
    }

    /// `sha` makes GitLab refuse the approval if the head moved.
    nonisolated static func approveRequest(host: RemoteHost, number: Int, sha: String?, token: String) -> URLRequest {
        var payload: [String: String] = [:]
        if let sha { payload["sha"] = sha }
        return RemoteAPI.withJSON(makeRequest(url: URL(string: "\(mergeRequestPath(host, number))/approve"), token: token),
                                  method: "POST", body: payload)
    }

    nonisolated static func noteRequest(host: RemoteHost, number: Int, body: String, token: String) -> URLRequest {
        RemoteAPI.withJSON(makeRequest(url: URL(string: "\(mergeRequestPath(host, number))/notes"), token: token),
                           method: "POST", body: ["body": body])
    }

    nonisolated static func requestChangesNoteBody(_ body: String) -> String {
        "\(body.trimmingCharacters(in: .whitespacesAndNewlines))\n\n/submit_review requested_changes"
    }

    nonisolated static func requestChangesMutationRequest(host: RemoteHost, number: Int, token: String) -> URLRequest {
        let query = """
        mutation($projectPath: ID!, $iid: String!) { \
        mergeRequestRequestChanges(input: {projectPath: $projectPath, iid: $iid}) { errors } }
        """
        return RemoteAPI.graphQL(makeRequest(url: nil, token: token), endpoint: graphQLEndpoint(for: host), query: query,
                                 variables: ["projectPath": host.slug, "iid": "\(number)"])
    }

    nonisolated private static func mergeRequestPath(_ host: RemoteHost, _ number: Int) -> String {
        "\(base(for: host))/projects/\(encodeSlug(host))/merge_requests/\(number)"
    }

    // MARK: Parsing

    nonisolated static func requestChangesSupport(_ info: GitLabInstanceInfo) -> RequestChangesSupport {
        if info.hasRequestChangesMutation { return .supported }
        if let version = info.version, version >= .requestChanges { return .supported }
        return .unsupported(reason: requestChangesUnsupportedReason)
    }

    nonisolated static func instanceInfo(version: Data?, mutations: Data?) -> GitLabInstanceInfo {
        GitLabInstanceInfo(version: version.flatMap(parseVersion),
                           hasRequestChangesMutation: mutations.map(parseHasRequestChangesMutation) ?? false)
    }

    nonisolated static func parseHasRequestChangesMutation(_ data: Data) -> Bool {
        nonisolated struct Schema: Decodable {
            let __type: SchemaType?
            struct SchemaType: Decodable { let fields: [Field]? }
            struct Field: Decodable { let name: String }
        }
        let schema = try? RemoteAPI.decodeGraphQL(data, as: Schema.self)
        return schema?.__type?.fields?.contains { $0.name == "mergeRequestRequestChanges" } ?? false
    }

    nonisolated static func parseViewerApproval(_ data: Data) -> ViewerApproval? {
        nonisolated struct Approvals: Decodable {
            let user_can_approve: Bool?
            let user_has_approved: Bool?
        }
        guard let approvals = try? JSONDecoder().decode(Approvals.self, from: data),
              let canApprove = approvals.user_can_approve,
              let hasApproved = approvals.user_has_approved else { return nil }
        return ViewerApproval(canApprove: canApprove, hasApproved: hasApproved)
    }

    nonisolated private static func parseVersion(_ data: Data) -> GitLabVersion? {
        nonisolated struct Body: Decodable { let version: String }
        return (try? JSONDecoder().decode(Body.self, from: data)).flatMap { GitLabVersion($0.version) }
    }
}
