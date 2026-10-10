import Foundation

/// GitHub REST v3 implementation of `PullRequestProvider`.
/// API reference: https://docs.github.com/en/rest/pulls/pulls
struct GitHubPullRequestProvider: PullRequestProvider {
    func fetchPulls(host: RemoteHost, state: PullListState, token: String) async throws -> [PullRequest] {
        guard var components = URLComponents(string: "\(Self.base(for: host))/repos/\(host.slug)/pulls") else {
            throw PullRequestFetchError.network("bad URL")
        }
        components.queryItems = [
            // `closed` includes merged PRs on GitHub.
            URLQueryItem(name: "state", value: state == .open ? "open" : "closed"),
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

        // CI status comes from a separate endpoint on the PR's head SHA;
        // approvals from /reviews (the PR object only lists who's requested).
        async let ciStatus = try? fetchCIStatus(host: host, sha: dto.head.sha, token: token)
        async let reviews = try? fetchReviews(host: host, number: number, token: token)
        let detail = dto.toModel(ciStatus: await ciStatus)
        guard let reviews = await reviews else { return detail }
        return PullRequestDetail(
            pull: detail.pull,
            descriptionMarkdown: detail.descriptionMarkdown,
            labels: detail.labels,
            reviewers: Self.reviewers(requested: (dto.requested_reviewers ?? []).map(\.login), reviews: reviews),
            assignees: detail.assignees,
            mergeable: detail.mergeable,
            ciStatus: detail.ciStatus
        )
    }

    func fetchCurrentUser(host: RemoteHost, token: String) async throws -> String {
        let data = try await RemoteAPI.send(Self.makeRequest(url: URL(string: "\(Self.base(for: host))/user"), token: token))
        struct UserDTO: Decodable { let login: String }
        do {
            return try JSONDecoder().decode(UserDTO.self, from: data).login
        } catch {
            throw PullRequestFetchError.decoding(error.localizedDescription)
        }
    }

    /// Check runs (GitHub Actions and other apps) plus legacy commit
    /// statuses: the combined status alone misses every Actions job.
    func fetchChecks(host: RemoteHost, pull: PullRequest, token: String) async throws -> [CICheck] {
        guard let sha = pull.headSha else { return [] }
        let base = "\(Self.base(for: host))/repos/\(host.slug)/commits/\(sha)"
        async let runs = RemoteAPI.send(Self.makeRequest(url: URL(string: "\(base)/check-runs?per_page=100"), token: token))
        async let statuses = RemoteAPI.send(Self.makeRequest(url: URL(string: "\(base)/status"), token: token))
        let runChecks = try Self.parseCheckRuns(await runs)
        // Statuses are optional extras; a failure there shouldn't hide the runs.
        let statusChecks = (try? Self.parseStatuses(await statuses)) ?? []
        return runChecks + statusChecks
    }

    private func fetchReviews(host: RemoteHost, number: Int, token: String) async throws -> [(login: String, state: String)] {
        let url = URL(string: "\(Self.base(for: host))/repos/\(host.slug)/pulls/\(number)/reviews?per_page=100")
        let data = try await RemoteAPI.send(Self.makeRequest(url: url, token: token))
        return try Self.parseReviews(data)
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

// MARK: - Parsers (static so the tests can feed them fixtures)

extension GitHubPullRequestProvider {
    static func parseCheckRuns(_ data: Data) throws -> [CICheck] {
        struct DTO: Decodable {
            let check_runs: [Run]
            struct Run: Decodable {
                let name: String
                let status: String          // queued, in_progress, completed, waiting, requested, pending
                let conclusion: String?     // success, failure, neutral, cancelled, skipped, timed_out, action_required, stale
                let started_at: String?
                let completed_at: String?
                let html_url: String?
                let details_url: String?
                let output: Output?
                let app: App?
                struct Output: Decodable { let title: String? }
                struct App: Decodable { let name: String? }
            }
        }
        let dto: DTO
        do { dto = try JSONDecoder().decode(DTO.self, from: data) } catch {
            throw PullRequestFetchError.decoding(error.localizedDescription)
        }
        return dto.check_runs.map { run in
            let state = checkRunState(status: run.status, conclusion: run.conclusion)
            let duration: TimeInterval? = {
                guard let start = RemoteAPI.parseDate(run.started_at),
                      let end = RemoteAPI.parseDate(run.completed_at) else { return nil }
                return end.timeIntervalSince(start)
            }()
            return CICheck(
                name: run.name,
                context: run.app?.name,
                state: state,
                duration: duration,
                failureMessage: state == .failed ? run.output?.title : nil,
                webURL: (run.html_url ?? run.details_url).flatMap(URL.init(string:))
            )
        }
    }

    static func checkRunState(status: String, conclusion: String?) -> CICheck.State {
        guard status == "completed" else { return status == "in_progress" ? .running : .queued }
        switch conclusion {
        case "success", "neutral": return .passed
        case "failure", "timed_out", "action_required", "startup_failure": return .failed
        case "cancelled", "stale": return .canceled
        case "skipped": return .skipped
        default: return .passed
        }
    }

    static func parseStatuses(_ data: Data) throws -> [CICheck] {
        struct DTO: Decodable {
            let statuses: [Status]
            struct Status: Decodable {
                let state: String           // error, failure, pending, success
                let context: String
                let description: String?
                let target_url: String?
            }
        }
        let dto = try JSONDecoder().decode(DTO.self, from: data)
        return dto.statuses.map { status in
            let state: CICheck.State = {
                switch status.state {
                case "success": return .passed
                case "failure", "error": return .failed
                default: return .running
                }
            }()
            return CICheck(
                name: status.context,
                context: "Status",
                state: state,
                duration: nil,
                failureMessage: state == .failed ? status.description : nil,
                webURL: status.target_url.flatMap(URL.init(string:))
            )
        }
    }

    static func parseReviews(_ data: Data) throws -> [(login: String, state: String)] {
        struct Review: Decodable {
            let user: User?
            let state: String               // APPROVED, CHANGES_REQUESTED, COMMENTED, DISMISSED, PENDING
            struct User: Decodable { let login: String }
        }
        let reviews = try JSONDecoder().decode([Review].self, from: data)
        return reviews.compactMap { review in review.user.map { ($0.login, review.state) } }
    }

    /// Requested reviewers are pending; each person who reviewed takes the
    /// state of their latest approving / requesting-changes / dismissed
    /// review (plain comments don't change it). Requested first, in order.
    static func reviewers(requested: [String], reviews: [(login: String, state: String)]) -> [PullRequestDetail.Reviewer] {
        var latest: [String: PullRequestDetail.Reviewer.State] = [:]
        var order: [String] = []
        for review in reviews {
            let state: PullRequestDetail.Reviewer.State?
            switch review.state {
            case "APPROVED": state = .approved
            case "CHANGES_REQUESTED": state = .changesRequested
            case "DISMISSED": state = .pending
            default: state = nil
            }
            guard let state else { continue }
            if latest[review.login] == nil { order.append(review.login) }
            latest[review.login] = state
        }
        var out: [PullRequestDetail.Reviewer] = requested.map { login in
            // Re-requested after reviewing: back to pending.
            .init(login: login, state: .pending)
        }
        for login in order where !requested.contains(login) {
            out.append(.init(login: login, state: latest[login] ?? .pending))
        }
        return out
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
    let head: HeadRef
    let base: Ref

    struct User: Decodable {
        let login: String
        let avatar_url: String?
    }
    struct Ref: Decodable { let ref: String }
    struct HeadRef: Decodable {
        let ref: String
        let sha: String?
    }

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
            updatedAt: RemoteAPI.parseDate(updated_at),
            headSha: head.sha
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
            updatedAt: RemoteAPI.parseDate(updated_at),
            headSha: head.sha
        )
        return PullRequestDetail(
            pull: pr,
            descriptionMarkdown: body,
            labels: labels?.map(\.name) ?? [],
            // GitHub REST v3 doesn't include approval status in the PR object;
            // it lives in /reviews. Kept simple here — show requested reviewers
            // as not-yet-approved.
            reviewers: (requested_reviewers ?? []).map { .init(login: $0.login, state: .pending) },
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
