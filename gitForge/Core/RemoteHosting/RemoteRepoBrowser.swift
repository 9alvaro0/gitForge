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

/// Browses the repos an account can see. Drives "My repos" in `CloneView`.
protocol RemoteRepoBrowsing: Sendable {
    /// One page of repos from the instance API at `apiBase`. `page` is
    /// 1-based; 50 results per page. An empty array means no more pages.
    func fetchUserRepos(apiBase: URL, token: String, page: Int) async throws -> [RemoteRepoSummary]
}

enum RemoteRepoBrowserFactory {
    static func make(for kind: HostingInstance.Kind, session: URLSession = RemoteAPI.session) -> any RemoteRepoBrowsing {
        switch kind {
        case .github: GitHubRepoBrowser(session: session)
        case .gitlab: GitLabRepoBrowser(session: session)
        }
    }
}

// MARK: - GitHub

struct GitHubRepoBrowser: RemoteRepoBrowsing {
    var session: URLSession = RemoteAPI.session

    func fetchUserRepos(apiBase: URL, token: String, page: Int) async throws -> [RemoteRepoSummary] {
        guard var components = URLComponents(url: apiBase.appendingPathComponent("user/repos"),
                                             resolvingAgainstBaseURL: false) else {
            throw PullRequestFetchError.network("bad URL")
        }
        components.queryItems = [
            URLQueryItem(name: "per_page", value: "50"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "direction", value: "desc"),
            URLQueryItem(name: "affiliation", value: "owner,collaborator,organization_member"),
        ]
        guard let url = components.url else { throw PullRequestFetchError.network("bad URL") }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("gitForge", forHTTPHeaderField: "User-Agent")

        let data = try await RemoteAPI.send(request, session: session)
        do {
            return try JSONDecoder().decode([GitHubRepoDTO].self, from: data).map { $0.toSummary() }
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
    var session: URLSession = RemoteAPI.session

    func fetchUserRepos(apiBase: URL, token: String, page: Int) async throws -> [RemoteRepoSummary] {
        guard var components = URLComponents(url: apiBase.appendingPathComponent("projects"),
                                             resolvingAgainstBaseURL: false) else {
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
        guard let url = components.url else { throw PullRequestFetchError.network("bad URL") }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("gitForge", forHTTPHeaderField: "User-Agent")

        let data = try await RemoteAPI.send(request, session: session)
        do {
            return try JSONDecoder().decode([GitLabProjectDTO].self, from: data).map { $0.toSummary() }
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
