import Foundation

/// Merging on GitLab: the project fixes the method and the squash policy;
/// the merge is one `PUT` that also asks GitLab to remove the source branch.
/// API reference: https://docs.gitlab.com/api/merge_requests/#merge-a-merge-request
extension GitLabPullRequestProvider {
    func fetchMergeOptions(host: RemoteHost, pull: PullRequest, detail: PullRequestDetail,
                           commits: [PullRequestCommit], token: String) async throws -> MergeOptions {
        let data = try await RemoteAPI.send(Self.projectRequest(host: host, token: token), session: session)
        let settings = try Self.parseProjectMergeSettings(data)
        return MergeOptions(kind: .gitlab(method: settings.method, squash: settings.squash),
                            canDeleteSourceBranch: detail.headInSameRepo == true,
                            initialMethod: nil, initialSquash: settings.squash != .never)
    }

    func merge(host: RemoteHost, pull: PullRequest, input: MergeInput, token: String) async throws -> MergeOutcome {
        do {
            _ = try await RemoteAPI.send(Self.mergeRequest(host: host, number: pull.number, input: input, token: token),
                                         session: session)
        } catch PullRequestFetchError.unauthorized {
            // GitLab's answer when the user can't merge, unless the token
            // itself is dead: then `/user` throws the 401 on and the store
            // refreshes the token.
            _ = try await RemoteAPI.send(Self.makeRequest(url: URL(string: "\(Self.base(for: host))/user"), token: token),
                                         session: session)
            throw PullRequestActionError.forbidden
        }
        return MergeOutcome(branchDeleted: input.deleteSourceBranch)
    }

    // MARK: Requests

    nonisolated static func projectRequest(host: RemoteHost, token: String) -> URLRequest {
        makeRequest(url: URL(string: "\(base(for: host))/projects/\(encodeSlug(host))"), token: token)
    }

    /// Messages travel only when the user edited them, so the project's
    /// templates apply otherwise; `sha` makes GitLab refuse a moved head.
    nonisolated static func mergeRequest(host: RemoteHost, number: Int, input: MergeInput, token: String) -> URLRequest {
        nonisolated struct Body: Encodable {
            let squash: Bool
            let should_remove_source_branch: Bool
            let sha: String?
            let squash_commit_message: String?
            let merge_commit_message: String?
        }
        let body = Body(squash: input.squash, should_remove_source_branch: input.deleteSourceBranch, sha: input.headSha,
                        squash_commit_message: input.messages[.squashMessage],
                        merge_commit_message: input.messages[.mergeMessage])
        let url = URL(string: "\(base(for: host))/projects/\(encodeSlug(host))/merge_requests/\(number)/merge")
        return RemoteAPI.withJSON(makeRequest(url: url, token: token), method: "PUT", body: body)
    }

    // MARK: Parsing

    /// A missing or unknown value reads as GitLab's defaults: merge commits,
    /// squash offered but off.
    nonisolated static func parseProjectMergeSettings(_ data: Data) throws -> (method: GitLabMergeMethod, squash: GitLabSquashOption) {
        nonisolated struct Project: Decodable {
            let merge_method: String?
            let squash_option: String?
        }
        let project: Project
        do {
            project = try JSONDecoder().decode(Project.self, from: data)
        } catch {
            throw PullRequestFetchError.decoding(error.localizedDescription)
        }
        return (project.merge_method.flatMap(GitLabMergeMethod.init(rawValue:)) ?? .merge,
                project.squash_option.flatMap(GitLabSquashOption.init(rawValue:)) ?? .defaultOff)
    }
}
