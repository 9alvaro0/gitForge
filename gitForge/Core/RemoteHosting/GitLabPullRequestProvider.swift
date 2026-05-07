import Foundation

/// GitLab REST v4 implementation of `PullRequestProvider`.
/// API reference: https://docs.gitlab.com/ee/api/merge_requests.html
struct GitLabPullRequestProvider: PullRequestProvider {
    func fetchOpen(host: RemoteHost, token: String) async throws -> [PullRequest] {
        guard var components = URLComponents(string: "\(Self.base(for: host))/projects/\(Self.encodeSlug(host))/merge_requests") else {
            throw PullRequestFetchError.network("bad URL")
        }
        components.queryItems = [
            URLQueryItem(name: "state", value: "opened"),
            URLQueryItem(name: "per_page", value: "50"),
            URLQueryItem(name: "order_by", value: "updated_at"),
            URLQueryItem(name: "sort", value: "desc"),
        ]
        let request = Self.makeRequest(url: components.url, token: token)
        let data = try await RemoteAPI.send(request)
        do {
            let decoded = try JSONDecoder().decode([GitLabMRDTO].self, from: data)
            return decoded.map { $0.toModel() }
        } catch {
            throw PullRequestFetchError.decoding(error.localizedDescription)
        }
    }

    func fetchDetail(host: RemoteHost, number: Int, token: String) async throws -> PullRequestDetail {
        let url = URL(string: "\(Self.base(for: host))/projects/\(Self.encodeSlug(host))/merge_requests/\(number)")
        let request = Self.makeRequest(url: url, token: token)
        let data = try await RemoteAPI.send(request)
        do {
            let dto = try JSONDecoder().decode(GitLabMRDetailDTO.self, from: data)
            return dto.toModel()
        } catch {
            throw PullRequestFetchError.decoding(error.localizedDescription)
        }
    }

    func fetchCommits(host: RemoteHost, number: Int, token: String) async throws -> [PullRequestCommit] {
        let url = URL(string: "\(Self.base(for: host))/projects/\(Self.encodeSlug(host))/merge_requests/\(number)/commits")
        let request = Self.makeRequest(url: url, token: token)
        let data = try await RemoteAPI.send(request)
        do {
            let decoded = try JSONDecoder().decode([GitLabCommitDTO].self, from: data)
            // GitLab returns newest-first; flip to chronological for consistency.
            return decoded.reversed().map { $0.toModel() }
        } catch {
            throw PullRequestFetchError.decoding(error.localizedDescription)
        }
    }

    func fetchFiles(host: RemoteHost, number: Int, token: String) async throws -> [PullRequestFileChange] {
        let url = URL(string: "\(Self.base(for: host))/projects/\(Self.encodeSlug(host))/merge_requests/\(number)/changes")
        let request = Self.makeRequest(url: url, token: token)
        let data = try await RemoteAPI.send(request)
        do {
            let dto = try JSONDecoder().decode(GitLabChangesDTO.self, from: data)
            return dto.changes.map { $0.toModel() }
        } catch {
            throw PullRequestFetchError.decoding(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private static func base(for host: RemoteHost) -> String {
        "https://\(host.host)/api/v4"
    }

    private static func encodeSlug(_ host: RemoteHost) -> String {
        host.slug.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? host.slug
    }

    private static func makeRequest(url: URL?, token: String) -> URLRequest {
        var request = URLRequest(url: url ?? URL(string: "https://gitlab.com")!)
        request.httpMethod = "GET"
        request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("gitForge", forHTTPHeaderField: "User-Agent")
        return request
    }
}

// MARK: - DTOs

private struct GitLabMRDTO: Decodable {
    let id: Int
    let iid: Int
    let title: String
    let state: String
    let draft: Bool?
    let work_in_progress: Bool?
    let web_url: String?
    let created_at: String?
    let updated_at: String?
    let source_branch: String
    let target_branch: String
    let author: Author?

    struct Author: Decodable {
        let username: String?
        let avatar_url: String?
    }

    func toModel() -> PullRequest {
        let isDraft = (draft == true) || (work_in_progress == true)
        let mappedState: PullRequest.State = {
            switch state {
            case "merged": return .merged
            case "closed": return .closed
            case "opened": return isDraft ? .draft : .open
            default:       return .open
            }
        }()
        return PullRequest(
            id: "\(iid)",
            number: iid,
            title: title,
            state: mappedState,
            authorLogin: author?.username,
            authorAvatarURL: author?.avatar_url.flatMap(URL.init(string:)),
            sourceBranch: source_branch,
            targetBranch: target_branch,
            webURL: web_url.flatMap(URL.init(string:)),
            createdAt: RemoteAPI.parseDate(created_at),
            updatedAt: RemoteAPI.parseDate(updated_at)
        )
    }
}

private struct GitLabMRDetailDTO: Decodable {
    let id: Int
    let iid: Int
    let title: String
    let state: String
    let draft: Bool?
    let work_in_progress: Bool?
    let web_url: String?
    let created_at: String?
    let updated_at: String?
    let source_branch: String
    let target_branch: String
    let author: User?
    let description: String?
    let labels: [String]?
    let reviewers: [User]?
    let assignees: [User]?
    let merge_status: String?
    let head_pipeline: Pipeline?

    struct User: Decodable {
        let username: String?
        let avatar_url: String?
    }
    struct Pipeline: Decodable {
        let status: String?      // "success", "failed", "running", "canceled", …
        let web_url: String?
    }

    func toModel() -> PullRequestDetail {
        let isDraft = (draft == true) || (work_in_progress == true)
        let mappedState: PullRequest.State = {
            switch state {
            case "merged": return .merged
            case "closed": return .closed
            case "opened": return isDraft ? .draft : .open
            default:       return .open
            }
        }()
        let pr = PullRequest(
            id: "\(iid)",
            number: iid,
            title: title,
            state: mappedState,
            authorLogin: author?.username,
            authorAvatarURL: author?.avatar_url.flatMap(URL.init(string:)),
            sourceBranch: source_branch,
            targetBranch: target_branch,
            webURL: web_url.flatMap(URL.init(string:)),
            createdAt: RemoteAPI.parseDate(created_at),
            updatedAt: RemoteAPI.parseDate(updated_at)
        )
        let mergeable: Bool? = {
            switch merge_status {
            case "can_be_merged", "mergeable":     return true
            case "cannot_be_merged", "conflict":   return false
            default:                                return nil
            }
        }()
        let ci: CIStatus? = {
            guard let pipeline = head_pipeline else { return nil }
            let mapped: CIStatus.State = {
                switch pipeline.status {
                case "success", "manual": return .success
                case "failed":             return .failure
                case "running", "pending", "preparing", "scheduled", "created":
                                          return .pending
                case "canceled":           return .canceled
                default:                   return .unknown
                }
            }()
            return CIStatus(state: mapped, description: pipeline.status,
                            webURL: pipeline.web_url.flatMap(URL.init(string:)))
        }()
        return PullRequestDetail(
            pull: pr,
            descriptionMarkdown: description,
            labels: labels ?? [],
            reviewers: (reviewers ?? []).compactMap {
                $0.username.map { PullRequestDetail.Reviewer(login: $0, approved: false) }
            },
            assignees: (assignees ?? []).compactMap(\.username),
            mergeable: mergeable,
            ciStatus: ci
        )
    }
}

private struct GitLabCommitDTO: Decodable {
    let id: String
    let title: String
    let author_name: String?
    let authored_date: String?

    func toModel() -> PullRequestCommit {
        PullRequestCommit(
            sha: id,
            subject: title,
            authorName: author_name,
            authorDate: RemoteAPI.parseDate(authored_date)
        )
    }
}

private struct GitLabChangesDTO: Decodable {
    let changes: [Change]

    struct Change: Decodable {
        let old_path: String
        let new_path: String
        let new_file: Bool?
        let renamed_file: Bool?
        let deleted_file: Bool?
        let diff: String

        func toModel() -> PullRequestFileChange {
            let status: PullRequestFileChange.Status = {
                if new_file == true { return .added }
                if deleted_file == true { return .deleted }
                if renamed_file == true { return .renamed }
                return .modified
            }()
            // GitLab doesn't return additions/deletions per file in this
            // payload — count them from the diff text.
            var adds = 0, dels = 0
            for line in diff.split(separator: "\n", omittingEmptySubsequences: false) {
                if line.hasPrefix("+") && !line.hasPrefix("+++") { adds += 1 }
                else if line.hasPrefix("-") && !line.hasPrefix("---") { dels += 1 }
            }
            return PullRequestFileChange(
                path: new_path,
                oldPath: old_path == new_path ? nil : old_path,
                status: status,
                additions: adds,
                deletions: dels,
                patch: diff
            )
        }
    }
}
