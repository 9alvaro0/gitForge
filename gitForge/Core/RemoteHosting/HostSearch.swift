import Foundation

/// A pull or merge request found by searching a whole host (spec §4.4).
nonisolated struct FoundPull: Equatable, Hashable, Sendable {
    let link: PullRequestLink
    let title: String
    let authorLogin: String
    let updatedAt: Date?
    let isDraft: Bool
}

/// A repo found by searching a whole host. `cloneURL` is the HTTPS one the
/// host reported.
nonisolated struct FoundRepo: Equatable, Hashable, Sendable {
    let host: RemoteHost
    let instanceId: UUID
    let cloneURL: String
}

/// What a search of one host answered with.
nonisolated struct HostSearchResults: Equatable, Sendable {
    var pulls: [FoundPull] = []
    var repos: [FoundRepo] = []
}

/// Searches a hosting instance for open pull/merge requests and repos, and
/// asks where a repo lives now. Feeds "Search all of <host>" in ⌘K and the
/// Reviews inbox's follow-the-rename lookup.
nonisolated protocol HostSearching: Sendable {
    /// Open pull/merge requests matching `text`, newest update first, at most
    /// `HostSearchFactory.resultLimit`. `owners`: `nil` = everything the token
    /// sees (an instance of your own). A list is for github.com and gitlab.com,
    /// where the owners are the first path segment of the account's repos:
    /// - GitHub limits the search to those owners with `user:` qualifiers; an
    ///   empty list adds none, so it searches everything, like `nil`.
    /// - GitLab takes any non-nil list to mean "this is gitlab.com": it reads
    ///   the merge requests group by group, so an empty list asks nothing.
    /// Requests whose URL isn't a link on `instance` are left out.
    func searchPulls(_ text: String, owners: [String]?, on instance: HostingInstance, token: String) async throws -> [FoundPull]

    /// Repos matching `text`, most recently active first, at most
    /// `HostSearchFactory.resultLimit`. `owners` as in `searchPulls` on GitHub;
    /// on GitLab, which takes no list of groups in a project search, any
    /// non-nil list (an empty one too) means gitlab.com and narrows the
    /// search to the account's own projects (`membership=true`).
    func searchRepos(_ text: String, owners: [String]?, on instance: HostingInstance, token: String) async throws -> [FoundRepo]

    /// The repo's path now (`owner/repo`), after a rename or a move; `nil`
    /// when the host doesn't know the repo (404). The host redirects a GET to
    /// the old path and the session follows it.
    func currentPath(of host: RemoteHost, token: String) async throws -> String?
}

enum HostSearchFactory {
    /// Pull requests, and repos, a search lists at most.
    nonisolated static let resultLimit = 10

    static func make(for kind: HostingInstance.Kind, session: URLSession = RemoteAPI.session) -> any HostSearching {
        switch kind {
        case .github: GitHubHostSearch(session: session)
        case .gitlab: GitLabHostSearch(session: session)
        }
    }
}

// MARK: - GitHub

/// `search/issues` for pull requests and `search/repositories` for repos.
/// Several `user:` qualifiers in one query add up: the results are those of
/// any of the owners (checked against the live API; the docs only say that a
/// query naming several resources answers with the ones the token can see).
/// API reference: https://docs.github.com/en/rest/search/search
nonisolated struct GitHubHostSearch: HostSearching {
    let session: URLSession

    func searchPulls(_ text: String, owners: [String]?, on instance: HostingInstance, token: String) async throws -> [FoundPull] {
        guard let text = HostSearchRequest.searchable(text) else { return [] }
        let terms = [text, "is:pr is:open archived:false"] + Self.ownerQualifiers(owners)
        let data = try await get("search/issues", on: instance.apiBaseURL, token: token, query: [
            ("q", terms.joined(separator: " ")),
            ("sort", "updated"),
            ("order", "desc"),
            ("per_page", String(HostSearchFactory.resultLimit)),
        ])
        let results: GitHubPullSearchDTO = try HostSearchRequest.decode(data)
        let pulls = results.items.compactMap { item -> FoundPull? in
            guard let title = item.title, let url = item.html_url,
                  let link = PullRequestLink.parse(url, instances: [instance]) else { return nil }
            return FoundPull(link: link, title: title, authorLogin: item.user?.login ?? "",
                             updatedAt: RemoteAPI.parseTimestamp(item.updated_at), isDraft: item.draft ?? false)
        }
        return Array(pulls.prefix(HostSearchFactory.resultLimit))
    }

    func searchRepos(_ text: String, owners: [String]?, on instance: HostingInstance, token: String) async throws -> [FoundRepo] {
        guard let text = HostSearchRequest.searchable(text) else { return [] }
        let data = try await get("search/repositories", on: instance.apiBaseURL, token: token, query: [
            ("q", ([text] + Self.ownerQualifiers(owners)).joined(separator: " ")),
            ("sort", "updated"),
            ("per_page", String(HostSearchFactory.resultLimit)),
        ])
        let results: GitHubRepoSearchDTO = try HostSearchRequest.decode(data)
        let repos = results.items.compactMap { item -> FoundRepo? in
            guard let fullName = item.full_name, let cloneURL = item.clone_url,
                  let host = RemoteHost.make(fullName: fullName, on: instance) else { return nil }
            return FoundRepo(host: host, instanceId: instance.id, cloneURL: cloneURL)
        }
        return Array(repos.prefix(HostSearchFactory.resultLimit))
    }

    func currentPath(of host: RemoteHost, token: String) async throws -> String? {
        guard let base = URL(string: GitHubPullRequestProvider.base(for: host)) else {
            throw PullRequestFetchError.network("bad URL")
        }
        do {
            let data = try await get("repos/\(host.slug)", on: base, token: token, query: [])
            return try HostSearchRequest.decode(data, as: GitHubRepoPathDTO.self).full_name
        } catch PullRequestFetchError.notFound {
            return nil
        }
    }

    private static func ownerQualifiers(_ owners: [String]?) -> [String] {
        (owners ?? []).filter { !$0.isEmpty }.map { "user:\($0)" }
    }

    private func get(_ endpoint: String, on apiBase: URL, token: String, query: [(String, String)]) async throws -> Data {
        let url = try HostSearchRequest.url(base: apiBase, endpoint: endpoint, query: query)
        return try await RemoteAPI.send(GitHubPullRequestProvider.makeRequest(url: url, token: token), session: session)
    }
}

nonisolated private struct GitHubPullSearchDTO: Decodable, Sendable {
    let items: [Item]

    struct Item: Decodable, Sendable {
        let title: String?
        let html_url: String?
        let draft: Bool?
        let updated_at: String?
        let user: User?

        struct User: Decodable, Sendable { let login: String? }
    }
}

nonisolated private struct GitHubRepoSearchDTO: Decodable, Sendable {
    let items: [Item]

    struct Item: Decodable, Sendable {
        let full_name: String?
        let clone_url: String?
    }
}

nonisolated private struct GitHubRepoPathDTO: Decodable, Sendable {
    let full_name: String
}

// MARK: - GitLab

/// `merge_requests` and `projects`. On gitlab.com the merge requests are read
/// group by group: its instance-wide list would search every public project.
/// API reference: https://docs.gitlab.com/api/merge_requests/ and https://docs.gitlab.com/api/projects/
nonisolated struct GitLabHostSearch: HostSearching {
    let session: URLSession

    func searchPulls(_ text: String, owners: [String]?, on instance: HostingInstance, token: String) async throws -> [FoundPull] {
        guard let text = HostSearchRequest.searchable(text) else { return [] }
        let query = [
            ("state", "opened"),
            ("search", text),
            ("order_by", "updated_at"),
            ("per_page", String(HostSearchFactory.resultLimit)),
        ]
        guard let owners else {
            // `scope` defaults to the account's own merge requests, and archived
            // projects are only left out when asked (a group's list leaves them out already).
            return try await mergeRequests("merge_requests", query: [("scope", "all"), ("non_archived", "true")] + query,
                                           on: instance, token: token)
        }

        // The groups at once. A group the account can't see (or that isn't
        // one: a personal namespace) is skipped; any other failure is the
        // search's.
        let found = try await withThrowingTaskGroup(of: (index: Int, pulls: [FoundPull]).self) { group in
            for (index, owner) in owners.enumerated() {
                group.addTask {
                    let endpoint = "groups/\(HostSearchRequest.encoded(owner))/merge_requests"
                    do {
                        return (index, try await mergeRequests(endpoint, query: query, on: instance, token: token))
                    } catch PullRequestFetchError.notFound {
                        return (index, [])
                    } catch PullRequestFetchError.forbidden {
                        return (index, [])
                    }
                }
            }
            var all: [(index: Int, pulls: [FoundPull])] = []
            for try await item in group { all.append(item) }
            return all
        }
        return Self.newestFirst(found.sorted { $0.index < $1.index }.flatMap(\.pulls))
    }

    func searchRepos(_ text: String, owners: [String]?, on instance: HostingInstance, token: String) async throws -> [FoundRepo] {
        guard let text = HostSearchRequest.searchable(text) else { return [] }
        var query = [
            ("search", text),
            ("simple", "true"),
            ("order_by", "last_activity_at"),
            ("per_page", String(HostSearchFactory.resultLimit)),
        ]
        // On gitlab.com, every public project would answer.
        if owners != nil { query.append(("membership", "true")) }
        let url = try HostSearchRequest.url(base: instance.apiBaseURL, endpoint: "projects", query: query)
        let data = try await RemoteAPI.send(GitLabPullRequestProvider.makeRequest(url: url, token: token), session: session)
        let projects: [GitLabProjectSearchDTO] = try HostSearchRequest.decode(data)
        let repos = projects.compactMap { project -> FoundRepo? in
            guard let fullName = project.path_with_namespace, let cloneURL = project.http_url_to_repo,
                  let host = RemoteHost.make(fullName: fullName, on: instance) else { return nil }
            return FoundRepo(host: host, instanceId: instance.id, cloneURL: cloneURL)
        }
        return Array(repos.prefix(HostSearchFactory.resultLimit))
    }

    func currentPath(of host: RemoteHost, token: String) async throws -> String? {
        guard let base = URL(string: GitLabPullRequestProvider.base(for: host)) else {
            throw PullRequestFetchError.network("bad URL")
        }
        do {
            let url = try HostSearchRequest.url(base: base, endpoint: "projects/\(GitLabPullRequestProvider.encodeSlug(host))", query: [])
            let data = try await RemoteAPI.send(GitLabPullRequestProvider.makeRequest(url: url, token: token), session: session)
            return try HostSearchRequest.decode(data, as: GitLabProjectPathDTO.self).path_with_namespace
        } catch PullRequestFetchError.notFound {
            return nil
        }
    }

    private func mergeRequests(_ endpoint: String, query: [(String, String)], on instance: HostingInstance,
                               token: String) async throws -> [FoundPull] {
        let url = try HostSearchRequest.url(base: instance.apiBaseURL, endpoint: endpoint, query: query)
        let data = try await RemoteAPI.send(GitLabPullRequestProvider.makeRequest(url: url, token: token), session: session)
        let requests: [GitLabMergeRequestSearchDTO] = try HostSearchRequest.decode(data)
        let pulls = requests.compactMap { request -> FoundPull? in
            guard let title = request.title, let url = request.web_url,
                  let link = PullRequestLink.parse(url, instances: [instance]) else { return nil }
            return FoundPull(link: link, title: title, authorLogin: request.author?.username ?? "",
                             updatedAt: RemoteAPI.parseTimestamp(request.updated_at),
                             isDraft: (request.draft ?? false) || (request.work_in_progress ?? false))
        }
        return Array(pulls.prefix(HostSearchFactory.resultLimit))
    }

    /// Without repeats, by update date descending (undated last, ties in the
    /// order they came in), cut at the limit.
    private static func newestFirst(_ pulls: [FoundPull]) -> [FoundPull] {
        var seen = Set<PullRequestLink>()
        let unique = pulls.filter { seen.insert($0.link).inserted }
        let sorted = unique.enumerated().sorted { lhs, rhs in
            switch (lhs.element.updatedAt, rhs.element.updatedAt) {
            case let (left?, right?) where left != right: left > right
            case (.some, .none): true
            case (.none, .some): false
            default: lhs.offset < rhs.offset
            }
        }
        return Array(sorted.map(\.element).prefix(HostSearchFactory.resultLimit))
    }
}

nonisolated private struct GitLabMergeRequestSearchDTO: Decodable, Sendable {
    let title: String?
    let web_url: String?
    let draft: Bool?
    let work_in_progress: Bool?
    let updated_at: String?
    let author: Author?

    struct Author: Decodable, Sendable { let username: String? }
}

/// The `simple=true` form of a project: no visibility or default branch.
nonisolated private struct GitLabProjectSearchDTO: Decodable, Sendable {
    let path_with_namespace: String?
    let http_url_to_repo: String?
}

nonisolated private struct GitLabProjectPathDTO: Decodable, Sendable {
    let path_with_namespace: String
}

// MARK: - Shared

nonisolated private enum HostSearchRequest {
    /// RFC 3986's unreserved characters: everything else in a query value
    /// (`&`, `#`, `+`, `=`, `%`, spaces, quotes, accents) travels
    /// percent-encoded, so the server reads the text as typed.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// The text without the spaces around it; `nil` when nothing is left to look for.
    static func searchable(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// `value` safe to put in a path segment or a query value.
    static func encoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    /// `<base>/<endpoint>?<name>=<value>&…`, with the values percent-encoded.
    static func url(base: URL, endpoint: String, query: [(String, String)]) throws -> URL {
        let root = base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(string: "\(root)/\(endpoint)") else {
            throw PullRequestFetchError.network("bad URL")
        }
        if !query.isEmpty {
            components.percentEncodedQuery = query
                .map { "\($0.0)=\(encoded($0.1))" }
                .joined(separator: "&")
        }
        guard let url = components.url else { throw PullRequestFetchError.network("bad URL") }
        return url
    }

    static func decode<T: Decodable>(_ data: Data, as type: T.Type = T.self) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw PullRequestFetchError.decoding(error.localizedDescription)
        }
    }
}
