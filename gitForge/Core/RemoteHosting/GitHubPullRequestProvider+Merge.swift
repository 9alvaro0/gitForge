import Foundation

/// Merging on GitHub: the repo's settings say which methods it allows and
/// what the commit messages default to; the merge itself is one `PUT`, and
/// the branch goes with a separate `DELETE`.
/// API reference: https://docs.github.com/en/rest/pulls/pulls#merge-a-pull-request
extension GitHubPullRequestProvider {
    func fetchMergeOptions(host: RemoteHost, pull: PullRequest, detail: PullRequestDetail,
                           commits: [PullRequestCommit], token: String) async throws -> MergeOptions {
        let data = try await RemoteAPI.send(Self.repoRequest(host: host, token: token), session: session)
        return Self.mergeOptions(settings: try Self.parseMergeSettings(data), pull: pull, detail: detail, commits: commits)
    }

    /// A branch that's already gone (the repo deletes merged branches)
    /// counts as deleted. Any other failure, a protected branch's 422
    /// included, leaves the merge standing and the branch reported as kept.
    func merge(host: RemoteHost, pull: PullRequest, input: MergeInput, token: String) async throws -> MergeOutcome {
        _ = try await RemoteAPI.send(Self.mergeRequest(host: host, number: pull.number, input: input, token: token),
                                     session: session)
        guard input.deleteSourceBranch else { return MergeOutcome(branchDeleted: false) }
        do {
            _ = try await RemoteAPI.send(Self.deleteBranchRequest(host: host, branch: pull.sourceBranch, token: token),
                                         session: session)
        } catch PullRequestFetchError.notFound {
            return MergeOutcome(branchDeleted: true)
        } catch PullRequestFetchError.server(422, let body)
                    where body.range(of: "Reference does not exist", options: .caseInsensitive) != nil {
            return MergeOutcome(branchDeleted: true)
        } catch {
            return MergeOutcome(branchDeleted: false)
        }
        return MergeOutcome(branchDeleted: true)
    }

    // MARK: Requests

    nonisolated static func repoRequest(host: RemoteHost, token: String) -> URLRequest {
        makeRequest(url: URL(string: "\(base(for: host))/repos/\(host.slug)"), token: token)
    }

    /// Titles and bodies travel only when the user edited them; `sha` makes
    /// GitHub refuse the merge if the head moved.
    nonisolated static func mergeRequest(host: RemoteHost, number: Int, input: MergeInput, token: String) -> URLRequest {
        nonisolated struct Body: Encodable {
            let merge_method: String
            let sha: String?
            let commit_title: String?
            let commit_message: String?
        }
        let body = Body(merge_method: (input.method ?? .merge).rawValue, sha: input.headSha,
                        commit_title: input.messages[.title], commit_message: input.messages[.body])
        let url = URL(string: "\(base(for: host))/repos/\(host.slug)/pulls/\(number)/merge")
        return RemoteAPI.withJSON(makeRequest(url: url, token: token), method: "PUT", body: body)
    }

    nonisolated static func deleteBranchRequest(host: RemoteHost, branch: String, token: String) -> URLRequest {
        let path = branch.addingPercentEncoding(withAllowedCharacters: refPathAllowed) ?? branch
        return makeRequest(url: URL(string: "\(base(for: host))/repos/\(host.slug)/git/refs/heads/\(path)"),
                           token: token, method: "DELETE")
    }

    /// Unreserved characters and `/`: a branch's slashes are part of the ref path.
    nonisolated private static let refPathAllowed =
        CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/")

    // MARK: Parsing

    nonisolated static func parseMergeSettings(_ data: Data) throws -> GitHubMergeSettings {
        nonisolated struct Repo: Decodable {
            let allow_squash_merge: Bool?
            let allow_merge_commit: Bool?
            let allow_rebase_merge: Bool?
            let squash_merge_commit_title: String?
            let squash_merge_commit_message: String?
            let merge_commit_title: String?
            let merge_commit_message: String?
        }
        let repo: Repo
        do {
            repo = try JSONDecoder().decode(Repo.self, from: data)
        } catch {
            throw PullRequestFetchError.decoding(error.localizedDescription)
        }
        return GitHubMergeSettings(allowSquash: repo.allow_squash_merge, allowMerge: repo.allow_merge_commit,
                                   allowRebase: repo.allow_rebase_merge,
                                   squashTitle: repo.squash_merge_commit_title, squashMessage: repo.squash_merge_commit_message,
                                   mergeTitle: repo.merge_commit_title, mergeMessage: repo.merge_commit_message)
    }

    /// The allowed methods (unknown counts as allowed), squash first when
    /// allowed, and the messages GitHub will write where that's certain.
    nonisolated static func mergeOptions(settings: GitHubMergeSettings, pull: PullRequest, detail: PullRequestDetail,
                                         commits: [PullRequestCommit]) -> MergeOptions {
        let allowed: [(MergeMethod, Bool?)] = [(.squash, settings.allowSquash), (.merge, settings.allowMerge),
                                               (.rebase, settings.allowRebase)]
        var methods = allowed.filter { $0.1 != false }.map(\.0)
        // GitHub always allows one; if it says none, let the merge call answer.
        if methods.isEmpty { methods = MergeMethod.allCases }

        let titled = "\(pull.title) (\(RemoteProvider.github.reference(pull.number)))"
        let description = detail.descriptionMarkdown ?? ""
        var squash: [MergeMessageField: String] = [:]
        switch settings.squashTitle {
        case "PR_TITLE": squash[.title] = titled
        case "COMMIT_OR_PR_TITLE":
            squash[.title] = commits.count == 1
                ? "\(commits[0].subject) (\(RemoteProvider.github.reference(pull.number)))" : titled
        default: break
        }
        switch settings.squashMessage {
        case "PR_BODY": squash[.body] = description
        case "BLANK": squash[.body] = ""
        default: break
        }
        var merge: [MergeMessageField: String] = [:]
        if settings.mergeTitle == "PR_TITLE" { merge[.title] = titled }
        switch settings.mergeMessage {
        case "PR_TITLE": merge[.body] = pull.title
        case "PR_BODY": merge[.body] = description
        case "BLANK": merge[.body] = ""
        default: break
        }

        return MergeOptions(kind: .github(methods: methods), canDeleteSourceBranch: detail.headInSameRepo == true,
                            defaultsByMethod: [.squash: squash, .merge: merge],
                            initialMethod: methods.contains(.squash) ? .squash : methods.first, initialSquash: false)
    }
}

/// A repo's merge settings (`GET /repos/{owner}/{repo}`). `nil` = the
/// field wasn't there (older Enterprise Server, limited token).
nonisolated struct GitHubMergeSettings: Equatable, Sendable {
    var allowSquash: Bool?
    var allowMerge: Bool?
    var allowRebase: Bool?
    var squashTitle: String?
    var squashMessage: String?
    var mergeTitle: String?
    var mergeMessage: String?
}
