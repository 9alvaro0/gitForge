import Foundation

/// Lightweight summary of a repo as listed by GitHub/GitLab API endpoints.
/// Enough to render a row in the clone picker and resolve the URL git needs.
struct RemoteRepoSummary: Sendable, Identifiable, Equatable {
    let id: String
    let name: String
    let fullName: String         // "owner/repo" (GitHub) or "group/repo" (GitLab)
    let description: String?
    let sshURL: String?
    let httpsURL: String
    let isPrivate: Bool
    let defaultBranch: String?
}

/// Browses repos a token-bearing user has access to. Drives the "My repos"
/// tab in `CloneView`.
protocol RemoteRepoBrowsing: Sendable {
    /// Fetches a single page of repos. `page` is 1-based; 50 results per page.
    /// Returns an empty array when there are no more pages.
    func fetchUserRepos(host: String, token: String, page: Int) async throws -> [RemoteRepoSummary]
}

enum RemoteRepoBrowserFactory {
    static func make(for provider: RemoteProvider) -> any RemoteRepoBrowsing {
        switch provider {
        case .github: return GitHubRepoBrowser()
        case .gitlab: return GitLabRepoBrowser()
        }
    }
}

// MARK: - GitHub

struct GitHubRepoBrowser: RemoteRepoBrowsing {
    func fetchUserRepos(host: String, token: String, page: Int) async throws -> [RemoteRepoSummary] {
        let base = host == "github.com" ? "https://api.github.com" : "https://\(host)/api/v3"
        guard var components = URLComponents(string: "\(base)/user/repos") else {
            throw PullRequestFetchError.network("bad URL")
        }
        components.queryItems = [
            URLQueryItem(name: "per_page", value: "50"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "direction", value: "desc"),
            URLQueryItem(name: "affiliation", value: "owner,collaborator,organization_member"),
        ]
        var request = URLRequest(url: components.url ?? URL(string: base)!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("gitForge", forHTTPHeaderField: "User-Agent")

        let data = try await RemoteAPI.send(request)
        do {
            let decoded = try JSONDecoder().decode([GitHubRepoDTO].self, from: data)
            return decoded.map { $0.toSummary() }
        } catch {
            throw PullRequestFetchError.decoding(error.localizedDescription)
        }
    }
}

private struct GitHubRepoDTO: Decodable {
    let id: Int
    let name: String
    let full_name: String
    let description: String?
    let `private`: Bool
    let ssh_url: String?
    let clone_url: String
    let default_branch: String?

    func toSummary() -> RemoteRepoSummary {
        RemoteRepoSummary(
            id: String(id),
            name: name,
            fullName: full_name,
            description: description,
            sshURL: ssh_url,
            httpsURL: clone_url,
            isPrivate: `private`,
            defaultBranch: default_branch
        )
    }
}

// MARK: - GitLab

struct GitLabRepoBrowser: RemoteRepoBrowsing {
    func fetchUserRepos(host: String, token: String, page: Int) async throws -> [RemoteRepoSummary] {
        guard var components = URLComponents(string: "https://\(host)/api/v4/projects") else {
            throw PullRequestFetchError.network("bad URL")
        }
        components.queryItems = [
            URLQueryItem(name: "membership", value: "true"),
            URLQueryItem(name: "simple", value: "false"),
            URLQueryItem(name: "order_by", value: "last_activity_at"),
            URLQueryItem(name: "sort", value: "desc"),
            URLQueryItem(name: "per_page", value: "50"),
            URLQueryItem(name: "page", value: String(page)),
        ]
        var request = URLRequest(url: components.url ?? URL(string: "https://\(host)/api/v4/projects")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("gitForge", forHTTPHeaderField: "User-Agent")

        let data = try await RemoteAPI.send(request)
        do {
            let decoded = try JSONDecoder().decode([GitLabProjectDTO].self, from: data)
            return decoded.map { $0.toSummary() }
        } catch {
            throw PullRequestFetchError.decoding(error.localizedDescription)
        }
    }
}

private struct GitLabProjectDTO: Decodable {
    let id: Int
    let name: String
    let path_with_namespace: String
    let description: String?
    let visibility: String?
    let ssh_url_to_repo: String?
    let http_url_to_repo: String
    let default_branch: String?

    func toSummary() -> RemoteRepoSummary {
        RemoteRepoSummary(
            id: String(id),
            name: name,
            fullName: path_with_namespace,
            description: description,
            sshURL: ssh_url_to_repo,
            httpsURL: http_url_to_repo,
            isPrivate: visibility != "public",
            defaultBranch: default_branch
        )
    }
}
