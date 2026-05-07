import Foundation
import os

extension RepositoryViewModel {
    /// Open the detail view for a PR/MR — clears any prior detail state and
    /// kicks off a parallel fetch of detail / commits / files.
    func selectPullRequest(_ pr: PullRequest) {
        selectedPullRequest = pr
        pullRequestDetail = nil
        pullRequestCommits = []
        pullRequestFiles = []
        pullRequestDetailError = nil
        Task { await loadPullRequestDetail() }
    }

    /// Close the detail view and clear cached data.
    func closePullRequestDetail() {
        selectedPullRequest = nil
        pullRequestDetail = nil
        pullRequestCommits = []
        pullRequestFiles = []
        pullRequestDetailError = nil
    }

    /// Fetch the three detail payloads in parallel. Errors are collected into
    /// `pullRequestDetailError` (any one failure surfaces an error state).
    func loadPullRequestDetail() async {
        guard let pr = selectedPullRequest, let host = pullRequestsHost else { return }
        guard !pullRequestDetailLoading else { return }
        guard let token = RemoteCredentialsStore.shared.token(for: host.host) else {
            pullRequestDetailError = "No token configured for \(host.host)."
            return
        }

        pullRequestDetailLoading = true
        pullRequestDetailError = nil
        defer { pullRequestDetailLoading = false }

        let provider = PullRequestProviderFactory.make(for: host)
        let number = pr.number

        async let detail = Self.safeFetch { try await provider.fetchDetail(host: host, number: number, token: token) }
        async let commits = Self.safeFetch { try await provider.fetchCommits(host: host, number: number, token: token) }
        async let files = Self.safeFetch { try await provider.fetchFiles(host: host, number: number, token: token) }

        let detailResult = await detail
        let commitsResult = await commits
        let filesResult = await files

        switch detailResult {
        case .success(let value): pullRequestDetail = value
        case .failure(let error): pullRequestDetailError = Self.message(for: error)
        }
        switch commitsResult {
        case .success(let value): pullRequestCommits = value
        case .failure(let error):
            if pullRequestDetailError == nil {
                pullRequestDetailError = Self.message(for: error)
            }
        }
        switch filesResult {
        case .success(let value): pullRequestFiles = value
        case .failure(let error):
            if pullRequestDetailError == nil {
                pullRequestDetailError = Self.message(for: error)
            }
        }
    }

    private static func safeFetch<T: Sendable>(_ block: @Sendable () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await block()) }
        catch { return .failure(error) }
    }

    private static func message(for error: Error) -> String {
        if let typed = error as? PullRequestFetchError {
            return typed.errorDescription ?? "Request failed"
        }
        return error.localizedDescription
    }

    /// Refresh the PR/MR list for the active repository. Resolution order:
    /// 1) detect remote host (`origin`); skip if not GitHub/GitLab
    /// 2) read token from Keychain; surface "needs token" if missing
    /// 3) hit provider, store results / error
    func loadPullRequests(force: Bool = false) async {
        guard !pullRequestsLoading else { return }

        // Throttle: don't re-hit the API more than once every 30s unless forced.
        if !force, let last = pullRequestsLastLoadedAt,
           Date().timeIntervalSince(last) < 30 {
            return
        }

        pullRequestsLoading = true
        pullRequestsError = nil
        defer { pullRequestsLoading = false }

        guard let host = await cli.remoteHost() else {
            pullRequestsHost = nil
            pullRequests = []
            pullRequestsRequiresToken = false
            pullRequestsError = nil
            return
        }
        pullRequestsHost = host
        Self.logger.info("Pulls: detected host \(host.host, privacy: .public) (\(host.provider.rawValue, privacy: .public))")

        guard let token = RemoteCredentialsStore.shared.token(for: host.host) else {
            pullRequests = []
            pullRequestsRequiresToken = true
            Self.logger.info("Pulls: no token for host \(host.host, privacy: .public)")
            return
        }
        pullRequestsRequiresToken = false

        let provider = PullRequestProviderFactory.make(for: host)
        do {
            let results = try await provider.fetchOpen(host: host, token: token)
            pullRequests = results
            pullRequestsLastLoadedAt = .now
        } catch let error as PullRequestFetchError {
            pullRequestsError = error.errorDescription
        } catch {
            pullRequestsError = error.localizedDescription
        }
    }
}
