import Foundation

/// GitHub REST v3 implementation of `PullRequestProvider`.
/// API reference: https://docs.github.com/en/rest/pulls/pulls
struct GitHubPullRequestProvider: PullRequestProvider {
    /// Used by the writes, the file list and the review threads, so tests
    /// can point them at a stub server; the older reads use `RemoteAPI.session`.
    var session: URLSession = RemoteAPI.session

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
        // The rows' verdicts, read alongside: the REST list doesn't carry
        // them. A read that fails leaves the rows without one.
        async let statuses = listStatuses(for: state, host: host, token: token)
        let request = Self.makeRequest(url: components.url, token: token)
        let data = try await RemoteAPI.send(request)
        let pulls: [PullRequest]
        do {
            pulls = try JSONDecoder().decode([GitHubPullDTO].self, from: data).map { $0.toModel() }
        } catch {
            throw PullRequestFetchError.decoding(error.localizedDescription)
        }
        guard let statuses = await statuses else { return pulls }
        return Self.applying(statuses, to: pulls)
    }

    /// The open list's verdicts; `nil` for the closed list, or when the read fails.
    private func listStatuses(for state: PullListState, host: RemoteHost, token: String) async -> [Int: PullListStatus]? {
        guard state == .open else { return nil }
        return try? await fetchListStatuses(host: host, token: token)
    }

    /// Each open pull request's verdict, by number, from one GraphQL read
    /// (`listStatusQuery`).
    private func fetchListStatuses(host: RemoteHost, token: String) async throws -> [Int: PullListStatus] {
        guard let url = Self.graphQLURL(for: host) else { return [:] }
        var request = Self.makeRequest(url: url, token: token, method: "POST")
        // `mergeStateStatus` is behind this preview on older servers; where
        // it's no longer a preview the header changes nothing.
        request.setValue("application/vnd.github.merge-info-preview+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "query": Self.listStatusQuery,
            "variables": ["owner": host.owner, "name": host.repo],
        ])
        return try Self.parseListStatuses(try await RemoteAPI.send(request))
    }

    func fetchDetail(host: RemoteHost, number: Int, token: String) async throws -> PullRequestDetail {
        let url = URL(string: "\(Self.base(for: host))/repos/\(host.slug)/pulls/\(number)")
        let request = Self.makeRequest(url: url, token: token)
        let data = try await RemoteAPI.send(request)
        let dto = try Self.decodeDetail(data)

        // CI status comes from a separate endpoint on the PR's head SHA;
        // approvals from /reviews (the PR object only lists who's requested).
        async let ciStatus = try? fetchCIStatus(host: host, sha: dto.head.sha, token: token)
        async let reviews = try? fetchReviews(host: host, number: number, token: token)
        // Merging needs write access, which only the repo says.
        async let repo = try? RemoteAPI.send(Self.makeRequest(url: URL(string: "\(Self.base(for: host))/repos/\(host.slug)"),
                                                              token: token))
        var detail = dto.toModel(ciStatus: await ciStatus)
        detail.viewerCanMerge = await repo.flatMap(Self.parseViewerCanMerge)
        guard let reviews = await reviews else { return detail }
        detail.reviewers = Self.reviewers(requested: (dto.requested_reviewers ?? []).map(\.login), reviews: reviews)
        return detail
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
        return try await fetchCommitChecks(host: host, sha: sha, token: token)
    }

    func fetchCommitChecks(host: RemoteHost, sha: String, token: String) async throws -> [CICheck] {
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

    /// Every page, up to the API's 3000 files: a review thread on file 101
    /// needs its file in the list.
    func fetchFiles(host: RemoteHost, number: Int, token: String) async throws -> [PullRequestFileChange] {
        try await RemoteAPI.collectPages(pageSize: Self.filesPageSize, maxPages: 30) { page in
            try await fetchFiles(host: host, number: number, page: page, token: token)
        }
    }

    nonisolated static let filesPageSize = 100

    private func fetchFiles(host: RemoteHost, number: Int, page: Int, token: String) async throws -> [PullRequestFileChange] {
        guard var components = URLComponents(string: "\(Self.base(for: host))/repos/\(host.slug)/pulls/\(number)/files") else {
            throw PullRequestFetchError.network("bad URL")
        }
        components.queryItems = [URLQueryItem(name: "per_page", value: "\(Self.filesPageSize)"),
                                 URLQueryItem(name: "page", value: "\(page)")]
        let request = Self.makeRequest(url: components.url, token: token)
        let data = try await RemoteAPI.send(request, session: session)
        do {
            let decoded = try JSONDecoder().decode([GitHubFileDTO].self, from: data)
            return decoded.map { $0.toModel() }
        } catch {
            throw PullRequestFetchError.decoding(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    nonisolated static func base(for host: RemoteHost) -> String {
        if let api = host.apiBaseURL { return api.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
        return host.host == "github.com" ? "https://api.github.com" : "https://\(host.host)/api/v3"
    }

    nonisolated static func makeRequest(url: URL?, token: String, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url ?? URL(string: "https://api.github.com")!)
        request.httpMethod = method
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
    /// The open pull requests' merge fields, newest first as the REST list
    /// reads them.
    static let listStatusQuery = """
        query($owner: String!, $name: String!) {
          repository(owner: $owner, name: $name) {
            pullRequests(states: OPEN, first: 50, orderBy: {field: UPDATED_AT, direction: DESC}) {
              nodes {
                number
                isDraft
                mergeable
                mergeStateStatus
                reviewDecision
                commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
              }
            }
          }
        }
        """

    /// The GraphQL endpoint next to the REST one: `api.github.com/graphql`,
    /// or `/api/graphql` on a GitHub Enterprise server.
    nonisolated static func graphQLURL(for host: RemoteHost) -> URL? {
        let rest = base(for: host)
        if rest.hasSuffix("/api/v3") { return URL(string: String(rest.dropLast("/v3".count)) + "/graphql") }
        return URL(string: rest + "/graphql")
    }

    /// The verdict of each pull request `listStatusQuery` returned, by
    /// number. Errors in the answer (a field the server lacks) leave out
    /// what they hit; no data at all is an empty map.
    static func parseListStatuses(_ data: Data) throws -> [Int: PullListStatus] {
        struct Answer: Decodable {
            let data: DataBlock?
            struct DataBlock: Decodable { let repository: Repository? }
            struct Repository: Decodable { let pullRequests: Connection }
            struct Connection: Decodable { let nodes: [Node?] }
            struct Node: Decodable {
                let number: Int
                let isDraft: Bool?
                let mergeable: String?
                let mergeStateStatus: String?
                let reviewDecision: String?
                let commits: Commits?
            }
            struct Commits: Decodable { let nodes: [CommitNode?] }
            struct CommitNode: Decodable { let commit: Commit }
            struct Commit: Decodable { let statusCheckRollup: Rollup? }
            struct Rollup: Decodable { let state: String? }
        }
        let answer: Answer
        do { answer = try JSONDecoder().decode(Answer.self, from: data) } catch {
            throw PullRequestFetchError.decoding(error.localizedDescription)
        }
        var out: [Int: PullListStatus] = [:]
        for node in answer.data?.repository?.pullRequests.nodes ?? [] {
            guard let node, node.isDraft != true else { continue }
            let checks = node.commits?.nodes.compactMap { $0 }.last?.commit.statusCheckRollup?.state
            out[node.number] = PullListStatus.gitHub(mergeable: node.mergeable, mergeState: node.mergeStateStatus,
                                                     reviewDecision: node.reviewDecision, checks: checks)
        }
        return out
    }

    /// `pulls` with the verdicts read for them: only open ones (a draft
    /// shows as one) take theirs.
    static func applying(_ statuses: [Int: PullListStatus], to pulls: [PullRequest]) -> [PullRequest] {
        pulls.map { pull in
            guard pull.state == .open, let status = statuses[pull.number] else { return pull }
            var pull = pull
            pull.listStatus = status
            return pull
        }
    }

    /// The PR object alone: no CI status, reviewers as requested.
    static func parseDetail(_ data: Data) throws -> PullRequestDetail {
        try decodeDetail(data).toModel(ciStatus: nil)
    }

    /// The repo's `permissions.push` for the signed-in account; `nil` when
    /// the answer doesn't say (no permissions block, not JSON).
    nonisolated static func parseViewerCanMerge(_ data: Data) -> Bool? {
        nonisolated struct Repo: Decodable {
            let permissions: Permissions?
            struct Permissions: Decodable { let push: Bool? }
        }
        return (try? JSONDecoder().decode(Repo.self, from: data))?.permissions?.push
    }

    fileprivate static func decodeDetail(_ data: Data) throws -> GitHubPullDetailDTO {
        do {
            return try JSONDecoder().decode(GitHubPullDetailDTO.self, from: data)
        } catch {
            throw PullRequestFetchError.decoding(error.localizedDescription)
        }
    }

    /// `mergeable_state` (spec §5). `blocked` doesn't say which rule, so the
    /// reasons gitForge knows go with it; anything unknown is still being
    /// worked out on GitHub's side.
    nonisolated static func mergeStatus(mergeableState: String?, targetBranch: String) -> HostMergeStatus {
        switch mergeableState {
        case "clean", "has_hooks":
            return HostMergeStatus(verdict: .ready)
        case "unstable":
            return HostMergeStatus(verdict: .ready, failingChecksOptional: true)
        case "blocked":
            return HostMergeStatus(verdict: .blocked, reasons: [String(localized: "branch protection rules")],
                                   includesLocalReasons: true)
        case "behind":
            return HostMergeStatus(verdict: .blocked, reasons: [String(localized: "branch is out of date with \(targetBranch)")])
        case "dirty":
            return HostMergeStatus(verdict: .blocked, reasons: [HostMergeStatus.conflicts])
        case "draft":
            return HostMergeStatus(verdict: .blocked, reasons: [HostMergeStatus.draft])
        default:
            return HostMergeStatus(verdict: .waiting, reasons: [HostMergeStatus.checking], stillComputing: true)
        }
    }

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
    let mergeable_state: String?
    let labels: [Label]?
    let requested_reviewers: [User]?
    let assignees: [User]?

    struct User: Decodable {
        let login: String
        let avatar_url: String?
    }
    struct Repo: Decodable { let full_name: String }
    struct Ref: Decodable {
        let ref: String
        let repo: Repo?
    }
    struct HeadRef: Decodable {
        let ref: String
        let sha: String
        /// `null` once the fork it came from is deleted.
        let repo: Repo?
    }
    struct Label: Decodable { let name: String }

    var headInSameRepo: Bool? {
        guard let head = head.repo?.full_name, let base = base.repo?.full_name else { return nil }
        return head.caseInsensitiveCompare(base) == .orderedSame
    }

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
            ciStatus: ciStatus,
            hostMergeStatus: GitHubPullRequestProvider.mergeStatus(mergeableState: mergeable_state, targetBranch: base.ref),
            headInSameRepo: headInSameRepo
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
