import Foundation

/// GitLab REST v4 implementation of `PullRequestProvider`.
/// API reference: https://docs.gitlab.com/ee/api/merge_requests.html
struct GitLabPullRequestProvider: PullRequestProvider {
    /// Used by the review writes and the instance probe, so tests can point
    /// them at a stub server; the reads predate it and use `RemoteAPI.session`.
    var session: URLSession = RemoteAPI.session

    func fetchPulls(host: RemoteHost, state: PullListState, token: String) async throws -> [PullRequest] {
        switch state {
        case .open:
            return try await fetchList(host: host, state: "opened", token: token)
        case .closed:
            // GitLab's `closed` excludes merged MRs: ask for both, newest first.
            async let merged = fetchList(host: host, state: "merged", token: token)
            async let closed = fetchList(host: host, state: "closed", token: token)
            return try await (merged + closed).sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        }
    }

    private func fetchList(host: RemoteHost, state: String, token: String) async throws -> [PullRequest] {
        guard var components = URLComponents(string: "\(Self.base(for: host))/projects/\(Self.encodeSlug(host))/merge_requests") else {
            throw PullRequestFetchError.network("bad URL")
        }
        components.queryItems = [
            URLQueryItem(name: "state", value: state),
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

    func fetchCurrentUser(host: RemoteHost, token: String) async throws -> String {
        let data = try await RemoteAPI.send(Self.makeRequest(url: URL(string: "\(Self.base(for: host))/user"), token: token))
        struct UserDTO: Decodable { let username: String }
        do {
            return try JSONDecoder().decode(UserDTO.self, from: data).username
        } catch {
            throw PullRequestFetchError.decoding(error.localizedDescription)
        }
    }

    /// Jobs of the MR's latest pipeline.
    func fetchChecks(host: RemoteHost, pull: PullRequest, token: String) async throws -> [CICheck] {
        let project = "\(Self.base(for: host))/projects/\(Self.encodeSlug(host))"
        let pipelines = try await RemoteAPI.send(Self.makeRequest(
            url: URL(string: "\(project)/merge_requests/\(pull.number)/pipelines?per_page=1"), token: token))
        guard let pipelineId = try Self.parseLatestPipelineId(pipelines) else { return [] }
        return try await fetchJobs(project: project, pipelineId: pipelineId, token: token)
    }

    func fetchCommitChecks(host: RemoteHost, sha: String, token: String) async throws -> [CICheck] {
        let project = "\(Self.base(for: host))/projects/\(Self.encodeSlug(host))"
        guard var components = URLComponents(string: "\(project)/pipelines") else {
            throw PullRequestFetchError.network("bad URL")
        }
        // Newest pipeline first: a re-run supersedes the earlier ones.
        components.queryItems = [URLQueryItem(name: "sha", value: sha),
                                 URLQueryItem(name: "order_by", value: "id"),
                                 URLQueryItem(name: "sort", value: "desc"),
                                 URLQueryItem(name: "per_page", value: "1")]
        let pipelines = try await RemoteAPI.send(Self.makeRequest(url: components.url, token: token))
        guard let pipelineId = try Self.parseLatestPipelineId(pipelines) else { return [] }
        return try await fetchJobs(project: project, pipelineId: pipelineId, token: token)
    }

    private func fetchJobs(project: String, pipelineId: Int, token: String) async throws -> [CICheck] {
        let jobs = try await RemoteAPI.send(Self.makeRequest(
            url: URL(string: "\(project)/pipelines/\(pipelineId)/jobs?per_page=100"), token: token))
        return try Self.parseJobs(jobs)
    }

    func fetchDetail(host: RemoteHost, number: Int, token: String) async throws -> PullRequestDetail {
        let url = URL(string: "\(Self.base(for: host))/projects/\(Self.encodeSlug(host))/merge_requests/\(number)")
        let request = Self.makeRequest(url: url, token: token)
        async let approvals = try? RemoteAPI.send(Self.makeRequest(
            url: URL(string: "\(Self.base(for: host))/projects/\(Self.encodeSlug(host))/merge_requests/\(number)/approvals"),
            token: token))
        let data = try await RemoteAPI.send(request)
        let approvalsData = await approvals
        let approvedBy = approvalsData.flatMap { try? Self.parseApprovers($0) } ?? []
        var detail = try Self.parseDetail(data, approvedBy: approvedBy)
        detail.viewerApproval = approvalsData.flatMap(Self.parseViewerApproval)
        return detail
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

    nonisolated static func base(for host: RemoteHost) -> String {
        if let api = host.apiBaseURL { return api.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
        return "https://\(host.host)/api/v4"
    }

    nonisolated static func encodeSlug(_ host: RemoteHost) -> String {
        host.slug.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? host.slug
    }

    /// `Bearer` works for personal and OAuth tokens alike (`PRIVATE-TOKEN`
    /// only for personal ones).
    nonisolated static func makeRequest(url: URL?, token: String, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url ?? URL(string: "https://gitlab.com")!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("gitForge", forHTTPHeaderField: "User-Agent")
        return request
    }
}

// MARK: - Parsers (static so the tests can feed them fixtures)

extension GitLabPullRequestProvider {
    static func parseDetail(_ data: Data, approvedBy: [String] = []) throws -> PullRequestDetail {
        do {
            return try JSONDecoder().decode(GitLabMRDetailDTO.self, from: data).toModel(approvedBy: approvedBy)
        } catch {
            throw PullRequestFetchError.decoding(error.localizedDescription)
        }
    }

    /// `detailed_merge_status` (GitLab 15.6+, spec §5), else the older
    /// `merge_status`; `nil` when neither is there.
    nonisolated static func mergeStatus(detailed: String?, legacy: String?) -> HostMergeStatus? {
        if let detailed {
            switch detailed {
            case "mergeable":
                return HostMergeStatus(verdict: .ready)
            case "checking", "unchecked", "preparing", "approvals_syncing":
                return HostMergeStatus(verdict: .waiting, reasons: [HostMergeStatus.checking])
            case "ci_still_running":
                return HostMergeStatus(verdict: .waiting, reasons: [String(localized: "the pipeline is still running")])
            default:
                return HostMergeStatus(verdict: .blocked, reasons: [blockedReason(detailed)])
            }
        }
        switch legacy {
        case nil:
            return nil
        case "can_be_merged":
            return HostMergeStatus(verdict: .ready)
        case "cannot_be_merged":
            return HostMergeStatus(verdict: .blocked, reasons: [HostMergeStatus.conflicts])
        default:
            return HostMergeStatus(verdict: .waiting, reasons: [HostMergeStatus.checking])
        }
    }

    nonisolated private static func blockedReason(_ status: String) -> String {
        switch status {
        case "not_approved": String(localized: "needs approval")
        case "ci_must_pass": String(localized: "the pipeline must pass")
        case "discussions_not_resolved": String(localized: "all threads must be resolved")
        case "conflict": HostMergeStatus.conflicts
        case "draft_status": HostMergeStatus.draft
        case "need_rebase": String(localized: "needs a rebase onto the target branch")
        case "requested_changes": String(localized: "a reviewer requested changes")
        case "blocked_status", "merge_request_blocked": String(localized: "blocked by another merge request")
        case "not_open": String(localized: "not open")
        case "external_status_checks": String(localized: "external status checks must pass")
        case "merge_time": String(localized: "can't merge before its scheduled time")
        case "jira_association_missing": String(localized: "needs a linked Jira issue")
        case "security_policy_violations": String(localized: "security policies aren't met")
        case "title_regex": String(localized: "the title doesn't match the project's rule")
        case "commits_status": String(localized: "commits don't meet the project's rules")
        case "locked_paths", "locked_lfs_files": String(localized: "touches locked files")
        default: String(localized: "the host doesn't allow merging yet")
        }
    }

    static func parseLatestPipelineId(_ data: Data) throws -> Int? {
        struct Pipeline: Decodable { let id: Int }
        return try JSONDecoder().decode([Pipeline].self, from: data).first?.id
    }

    static func parseJobs(_ data: Data) throws -> [CICheck] {
        struct Job: Decodable {
            let name: String
            let stage: String?
            let status: String              // created, pending, running, failed, success, canceled, skipped, manual, scheduled, waiting_for_resource, preparing
            let duration: Double?
            let web_url: String?
            let failure_reason: String?
        }
        let jobs: [Job]
        do { jobs = try JSONDecoder().decode([Job].self, from: data) } catch {
            throw PullRequestFetchError.decoding(error.localizedDescription)
        }
        return jobs.map { job in
            let state = jobState(job.status)
            return CICheck(
                name: job.name,
                context: job.stage,
                state: state,
                duration: job.duration,
                failureMessage: state == .failed ? job.failure_reason?.replacingOccurrences(of: "_", with: " ") : nil,
                webURL: job.web_url.flatMap(URL.init(string:))
            )
        }
    }

    static func jobState(_ status: String) -> CICheck.State {
        switch status {
        case "success": return .passed
        case "failed": return .failed
        case "running": return .running
        case "canceled": return .canceled
        case "skipped", "manual": return .skipped
        default: return .queued
        }
    }

    static func parseApprovers(_ data: Data) throws -> [String] {
        struct Approvals: Decodable {
            let approved_by: [Entry]?
            struct Entry: Decodable { let user: User }
            struct User: Decodable { let username: String }
        }
        return try JSONDecoder().decode(Approvals.self, from: data).approved_by?.map(\.user.username) ?? []
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
    let sha: String?

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
            updatedAt: RemoteAPI.parseDate(updated_at),
            headSha: sha
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
    let detailed_merge_status: String?
    let source_project_id: Int?
    let target_project_id: Int?
    let head_pipeline: Pipeline?
    let sha: String?

    struct User: Decodable {
        let username: String?
        let avatar_url: String?
    }
    struct Pipeline: Decodable {
        let status: String?      // "success", "failed", "running", "canceled", …
        let web_url: String?
    }

    func toModel(approvedBy: [String] = []) -> PullRequestDetail {
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
            updatedAt: RemoteAPI.parseDate(updated_at),
            headSha: sha
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
            reviewers: GitLabPullRequestProvider.reviewers(requested: (reviewers ?? []).compactMap(\.username), approvedBy: approvedBy),
            assignees: (assignees ?? []).compactMap(\.username),
            mergeable: mergeable,
            ciStatus: ci,
            hostMergeStatus: GitLabPullRequestProvider.mergeStatus(detailed: detailed_merge_status, legacy: merge_status),
            headInSameRepo: source_project_id.flatMap { source in target_project_id.map { $0 == source } }
        )
    }
}

extension GitLabPullRequestProvider {
    /// Assigned reviewers, approved when they're among the approvers; then
    /// any other approver.
    static func reviewers(requested: [String], approvedBy: [String]) -> [PullRequestDetail.Reviewer] {
        var out = requested.map { PullRequestDetail.Reviewer(login: $0, state: approvedBy.contains($0) ? .approved : .pending) }
        for login in approvedBy where !requested.contains(login) {
            out.append(.init(login: login, state: .approved))
        }
        return out
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
