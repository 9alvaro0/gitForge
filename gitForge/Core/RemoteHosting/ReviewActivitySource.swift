import Foundation

/// One sign that the account touched a repo: an event on GitLab, a pull
/// request it is involved in on GitHub.
nonisolated struct ActivityHit: Equatable, Sendable {
    /// How the host names the repo: GitLab events carry the project id,
    /// GitHub search results the `owner/repo` path.
    nonisolated enum Ref: Hashable, Sendable {
        case path(String)
        case projectId(String)
    }

    let ref: Ref
    let at: Date
}

/// Reads which repos an account has recently opened, reviewed or commented
/// pull requests in. Feeds the repos the Reviews inbox follows.
protocol ReviewActivitySource: Sendable {
    /// Hits since `since` (the host filters by UTC calendar day), in the
    /// order the host returned them.
    func recentActivity(apiBase: URL, login: String, since: Date, token: String) async throws -> [ActivityHit]
}

enum ReviewActivitySourceFactory {
    static func make(for kind: HostingInstance.Kind, session: URLSession = RemoteAPI.session) -> any ReviewActivitySource {
        switch kind {
        case .github: GitHubReviewActivity(session: session)
        case .gitlab: GitLabReviewActivity(session: session)
        }
    }
}

// MARK: - GitLab

/// The account's own `/events`: pushes, merge requests, comments and so on,
/// each tagged with its project id.
/// API reference: https://docs.gitlab.com/api/events/
struct GitLabReviewActivity: ReviewActivitySource {
    var session: URLSession = RemoteAPI.session

    /// Up to 5 pages of 100, or until the first page that comes back short.
    nonisolated static let pageSize = 100
    nonisolated static let maxPages = 5

    /// `/events` is always the authenticated user's, so `login` isn't needed.
    func recentActivity(apiBase: URL, login: String, since: Date, token: String) async throws -> [ActivityHit] {
        let after = ActivityQueryDate.string(from: since)
        let events = try await RemoteAPI.collectPages(pageSize: Self.pageSize, maxPages: Self.maxPages) { page in
            try await fetchEvents(apiBase: apiBase, after: after, page: page, token: token)
        }
        return events.compactMap { event in
            guard let projectId = event.project_id, let at = RemoteAPI.parseTimestamp(event.created_at) else { return nil }
            return ActivityHit(ref: .projectId(String(projectId)), at: at)
        }
    }

    private func fetchEvents(apiBase: URL, after: String, page: Int, token: String) async throws -> [GitLabEventDTO] {
        guard var components = URLComponents(url: apiBase.appendingPathComponent("events"),
                                             resolvingAgainstBaseURL: false) else {
            throw PullRequestFetchError.network("bad URL")
        }
        components.queryItems = [
            URLQueryItem(name: "after", value: after),
            URLQueryItem(name: "per_page", value: String(Self.pageSize)),
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
            return try JSONDecoder().decode([GitLabEventDTO].self, from: data)
        } catch {
            throw PullRequestFetchError.decoding(error.localizedDescription)
        }
    }
}

/// Only the two fields the inbox needs. Events with no project (personal
/// snippets, say) decode with a nil `project_id` and are dropped.
nonisolated private struct GitLabEventDTO: Decodable, Sendable {
    let project_id: Int?
    let created_at: String?
}

// MARK: - GitHub

/// A search for the pull requests the account is involved in (author,
/// assignee, reviewer, commenter or mentioned), updated since the date.
/// One page of 100, the most recently updated: the search API caps what it
/// returns anyway.
/// API reference: https://docs.github.com/en/rest/search/search#search-issues-and-pull-requests
struct GitHubReviewActivity: ReviewActivitySource {
    var session: URLSession = RemoteAPI.session

    nonisolated static let pageSize = 100

    func recentActivity(apiBase: URL, login: String, since: Date, token: String) async throws -> [ActivityHit] {
        guard var components = URLComponents(url: apiBase.appendingPathComponent("search/issues"),
                                             resolvingAgainstBaseURL: false) else {
            throw PullRequestFetchError.network("bad URL")
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: "is:pr involves:\(login) updated:>=\(ActivityQueryDate.string(from: since))"),
            // Newest first: past the one page, the oldest drop out, not the least relevant.
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "order", value: "desc"),
            URLQueryItem(name: "per_page", value: String(Self.pageSize)),
        ]
        guard let url = components.url else { throw PullRequestFetchError.network("bad URL") }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("gitForge", forHTTPHeaderField: "User-Agent")

        let data = try await RemoteAPI.send(request, session: session)
        let results: GitHubSearchDTO
        do {
            results = try JSONDecoder().decode(GitHubSearchDTO.self, from: data)
        } catch {
            throw PullRequestFetchError.decoding(error.localizedDescription)
        }
        return results.items.compactMap { item in
            guard let path = Self.repositoryPath(fromAPIURL: item.repository_url),
                  let at = RemoteAPI.parseTimestamp(item.updated_at) else { return nil }
            return ActivityHit(ref: .path(path), at: at)
        }
    }

    /// `owner/repo` out of `https://api.github.com/repos/owner/repo` (or an
    /// Enterprise `…/api/v3/repos/owner/repo`): the last two segments, as
    /// long as they follow a `repos` one.
    nonisolated static func repositoryPath(fromAPIURL raw: String?) -> String? {
        guard let raw, let url = URL(string: raw) else { return nil }
        let segments = url.pathComponents.filter { $0 != "/" }.suffix(3)
        guard segments.count == 3, segments.first == "repos" else { return nil }
        return segments.dropFirst().joined(separator: "/")
    }
}

nonisolated private struct GitHubSearchDTO: Decodable, Sendable {
    let items: [Item]

    struct Item: Decodable, Sendable {
        let repository_url: String?
        let updated_at: String?
    }
}

// MARK: - Dates

nonisolated private enum ActivityQueryDate {
    /// The UTC calendar day as `yyyy-MM-dd`, whatever the Mac's time zone.
    static func string(from date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day())
    }
}

// MARK: - Matching

/// Keeps the activity that happened in repos the account is a member of.
nonisolated enum ActivityMatcher {
    /// One result per member repo that has any hit, with the newest hit's
    /// date, in the order of `members`. GitLab hits match by project id,
    /// GitHub hits by full name without regard to case. Hits in repos
    /// outside `members` are dropped.
    static func match(_ hits: [ActivityHit], members: [RemoteRepoSummary]) -> [(summary: RemoteRepoSummary, at: Date)] {
        var newestByProject: [String: Date] = [:]
        var newestByPath: [String: Date] = [:]
        for hit in hits {
            switch hit.ref {
            case .projectId(let id):
                newestByProject[id] = max(hit.at, newestByProject[id] ?? .distantPast)
            case .path(let path):
                let key = path.lowercased()
                newestByPath[key] = max(hit.at, newestByPath[key] ?? .distantPast)
            }
        }

        var seen = Set<String>()
        var matched: [(summary: RemoteRepoSummary, at: Date)] = []
        for member in members where seen.insert(member.id).inserted {
            let dates = [newestByProject[member.id], newestByPath[member.fullName.lowercased()]].compactMap { $0 }
            if let at = dates.max() { matched.append((summary: member, at: at)) }
        }
        return matched
    }
}
