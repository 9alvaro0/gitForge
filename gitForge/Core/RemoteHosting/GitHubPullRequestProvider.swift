import Foundation

/// GitHub REST v3 implementation of `PullRequestProvider`.
/// API reference: https://docs.github.com/en/rest/pulls/pulls
struct GitHubPullRequestProvider: PullRequestProvider {
    func fetchOpen(host: RemoteHost, token: String) async throws -> [PullRequest] {
        guard var components = URLComponents(string: "\(Self.base(for: host))/repos/\(host.slug)/pulls") else {
            throw PullRequestFetchError.network("bad URL")
        }
        components.queryItems = [
            URLQueryItem(name: "state", value: "open"),
            URLQueryItem(name: "per_page", value: "50"),
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "direction", value: "desc"),
        ]
        let request = Self.makeRequest(url: components.url, token: token)
        let data = try await RemoteAPI.send(request)
        do {
            let decoded = try JSONDecoder().decode([GitHubPullDTO].self, from: data)
            return decoded.map { $0.toModel() }
        } catch {
            throw PullRequestFetchError.decoding(error.localizedDescription)
        }
    }

    func fetchDetail(host: RemoteHost, number: Int, token: String) async throws -> PullRequestDetail {
        let url = URL(string: "\(Self.base(for: host))/repos/\(host.slug)/pulls/\(number)")
        let request = Self.makeRequest(url: url, token: token)
        let data = try await RemoteAPI.send(request)
        let dto: GitHubPullDetailDTO
        do {
            dto = try JSONDecoder().decode(GitHubPullDetailDTO.self, from: data)
        } catch {
            throw PullRequestFetchError.decoding(error.localizedDescription)
        }

        // CI status comes from a separate endpoint on the PR's head SHA.
        let ciStatus = try? await fetchCIStatus(host: host, sha: dto.head.sha, token: token)
        return dto.toModel(ciStatus: ciStatus)
    }

    func fetchCommits(host: RemoteHost, number: Int, token: String) async throws -> [PullRequestCommit] {
        guard var components = URLComponents(string: "\(Self.base(for: host))/repos/\(host.slug)/pulls/\(number)/commits") else {
            throw PullRequestFetchError.network("bad URL")
        }
        components.queryItems = [URLQueryItem(name: "per_page", value: "100")]
        let request = Self.makeRequest(url: components.url, token: token)
        let data = try await RemoteAPI.send(request)
        do {
            let decoded = try JSONDecoder().decode([GitHubCommitDTO].self, from: data)
            return decoded.map { $0.toModel() }
        } catch {
            throw PullRequestFetchError.decoding(error.localizedDescription)
        }
    }

    func fetchFiles(host: RemoteHost, number: Int, token: String) async throws -> [PullRequestFileChange] {
        guard var components = URLComponents(string: "\(Self.base(for: host))/repos/\(host.slug)/pulls/\(number)/files") else {
            throw PullRequestFetchError.network("bad URL")
        }
        components.queryItems = [URLQueryItem(name: "per_page", value: "100")]
        let request = Self.makeRequest(url: components.url, token: token)
        let data = try await RemoteAPI.send(request)
        do {
            let decoded = try JSONDecoder().decode([GitHubFileDTO].self, from: data)
            return decoded.map { $0.toModel() }
        } catch {
            throw PullRequestFetchError.decoding(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private static func base(for host: RemoteHost) -> String {
        host.host == "github.com" ? "https://api.github.com" : "https://\(host.host)/api/v3"
    }

    private static func makeRequest(url: URL?, token: String) -> URLRequest {
        var request = URLRequest(url: url ?? URL(string: "https://api.github.com")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("gitForge", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func fetchCIStatus(host: RemoteHost, sha: String, token: String) async throws -> CIStatus? {
        // `combined-status` aggregates all status checks for a commit into a
        // single state — exactly what we want to show in the header pill.
        let url = URL(string: "\(Self.base(for: host))/repos/\(host.slug)/commits/\(sha)/status")
        let request = Self.makeRequest(url: url, token: token)
        let data = try await RemoteAPI.send(request)
        struct StatusDTO: Decodable {
            let state: String       // "success", "failure", "pending", "error"
            let total_count: Int
            let statuses: [Detail]
            struct Detail: Decodable { let target_url: String? }
        }
        let dto = try JSONDecoder().decode(StatusDTO.self, from: data)
        guard dto.total_count > 0 else { return nil }
        let state: CIStatus.State = {
            switch dto.state {
            case "success": return .success
            case "failure", "error": return .failure
            case "pending": return .pending
            default: return .unknown
            }
        }()
        return CIStatus(state: state, description: nil, webURL: dto.statuses.first?.target_url.flatMap(URL.init(string:)))
    }
}

// MARK: - DTOs

private struct GitHubPullDTO: Decodable {
    let id: Int
    let number: Int
    let title: String
    let state: String
    let draft: Bool?
    let merged_at: String?
    let html_url: String?
    let created_at: String?
    let updated_at: String?
    let user: User?
    let head: Ref
    let base: Ref

    struct User: Decodable {
        let login: String
        let avatar_url: String?
    }
    struct Ref: Decodable { let ref: String }

    func toModel() -> PullRequest {
        let mappedState: PullRequest.State = {
            if merged_at != nil { return .merged }
            if draft == true { return .draft }
            return state == "closed" ? .closed : .open
        }()
        return PullRequest(
            id: String(id),
            number: number,
            title: title,
            state: mappedState,
            authorLogin: user?.login,
            authorAvatarURL: user?.avatar_url.flatMap(URL.init(string:)),
            sourceBranch: head.ref,
            targetBranch: base.ref,
            webURL: html_url.flatMap(URL.init(string:)),
            createdAt: RemoteAPI.parseDate(created_at),
            updatedAt: RemoteAPI.parseDate(updated_at)
        )
    }
}

private struct GitHubPullDetailDTO: Decodable {
    let id: Int
    let number: Int
    let title: String
    let state: String
    let draft: Bool?
    let merged_at: String?
    let html_url: String?
    let created_at: String?
    let updated_at: String?
    let user: User?
    let head: HeadRef
    let base: Ref
    let body: String?
    let mergeable: Bool?
    let labels: [Label]?
    let requested_reviewers: [User]?
    let assignees: [User]?

    struct User: Decodable {
        let login: String
        let avatar_url: String?
    }
    struct Ref: Decodable { let ref: String }
    struct HeadRef: Decodable {
        let ref: String
        let sha: String
    }
    struct Label: Decodable { let name: String }

    func toModel(ciStatus: CIStatus?) -> PullRequestDetail {
        let mappedState: PullRequest.State = {
            if merged_at != nil { return .merged }
            if draft == true { return .draft }
            return state == "closed" ? .closed : .open
        }()
        let pr = PullRequest(
            id: String(id),
            number: number,
            title: title,
            state: mappedState,
            authorLogin: user?.login,
            authorAvatarURL: user?.avatar_url.flatMap(URL.init(string:)),
            sourceBranch: head.ref,
            targetBranch: base.ref,
            webURL: html_url.flatMap(URL.init(string:)),
            createdAt: RemoteAPI.parseDate(created_at),
            updatedAt: RemoteAPI.parseDate(updated_at)
        )
        return PullRequestDetail(
            pull: pr,
            descriptionMarkdown: body,
            labels: labels?.map(\.name) ?? [],
            // GitHub REST v3 doesn't include approval status in the PR object;
            // it lives in /reviews. Kept simple here — show requested reviewers
            // as not-yet-approved.
            reviewers: (requested_reviewers ?? []).map { .init(login: $0.login, approved: false) },
            assignees: (assignees ?? []).map(\.login),
            mergeable: mergeable,
            ciStatus: ciStatus
        )
    }
}

private struct GitHubCommitDTO: Decodable {
    let sha: String
    let commit: Inner

    struct Inner: Decodable {
        let message: String
        let author: Author?
    }
    struct Author: Decodable {
        let name: String?
        let date: String?
    }

    func toModel() -> PullRequestCommit {
        let firstLine = commit.message.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? commit.message
        return PullRequestCommit(
            sha: sha,
            subject: firstLine,
            authorName: commit.author?.name,
            authorDate: RemoteAPI.parseDate(commit.author?.date)
        )
    }
}

private struct GitHubFileDTO: Decodable {
    let filename: String
    let previous_filename: String?
    let status: String
    let additions: Int
    let deletions: Int
    let patch: String?

    func toModel() -> PullRequestFileChange {
        let mapped: PullRequestFileChange.Status = {
            switch status {
            case "added":    return .added
            case "removed":  return .deleted
            case "modified": return .modified
            case "renamed":  return .renamed
            case "copied":   return .copied
            default:         return .other(status)
            }
        }()
        return PullRequestFileChange(
            path: filename,
            oldPath: previous_filename,
            status: mapped,
            additions: additions,
            deletions: deletions,
            patch: patch
        )
    }
}
