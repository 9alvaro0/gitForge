import Foundation

/// Errors surfaced by remote PR/MR fetches. Mapped to friendly UI strings.
enum PullRequestFetchError: LocalizedError, Sendable, Equatable {
    case missingToken
    case unauthorized
    case forbidden
    case notFound
    case network(String)
    case tls(String)
    case decoding(String)
    case server(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            "No token configured for this host. Add a Personal Access Token in Settings."
        case .unauthorized:
            "The token was rejected. Check that it's valid and has the required scopes."
        case .forbidden:
            "The token doesn't have permission to read pull requests for this repo."
        case .notFound:
            "Repository not found on the remote host."
        case .network(let message):
            "Network error: \(message)"
        case .tls(let message):
            "TLS error: \(message). Likely a self-signed or untrusted certificate."
        case .decoding(let message):
            "Couldn't read the response: \(message)"
        case .server(let code, let message):
            "Server returned \(code): \(message)"
        }
    }
}

/// Abstracts the platform-specific API calls for PR/MR list and detail.
protocol PullRequestProvider: Sendable {
    /// Fetch the open, or the closed and merged, PRs/MRs for the given repo
    /// coordinates, newest update first. Empty array on no results.
    func fetchPulls(host: RemoteHost, state: PullListState, token: String) async throws -> [PullRequest]

    /// Login of the token's owner, for the "Mine" filter.
    func fetchCurrentUser(host: RemoteHost, token: String) async throws -> String

    /// CI jobs for the PR's head commit (GitHub check runs and statuses,
    /// GitLab jobs of the MR's latest pipeline).
    func fetchChecks(host: RemoteHost, pull: PullRequest, token: String) async throws -> [CICheck]

    /// Fetch the full detail (description, reviewers, labels, CI status…)
    /// for a single PR/MR identified by its number.
    func fetchDetail(host: RemoteHost, number: Int, token: String) async throws -> PullRequestDetail

    /// Fetch the commits in a PR/MR, ordered chronologically (oldest first).
    func fetchCommits(host: RemoteHost, number: Int, token: String) async throws -> [PullRequestCommit]

    /// Fetch the changed files (with unified-diff patches when available).
    func fetchFiles(host: RemoteHost, number: Int, token: String) async throws -> [PullRequestFileChange]
}

/// Resolves the right provider for a `RemoteHost`.
enum PullRequestProviderFactory {
    static func make(for host: RemoteHost) -> PullRequestProvider {
        switch host.provider {
        case .github: return GitHubPullRequestProvider()
        case .gitlab: return GitLabPullRequestProvider()
        }
    }
}

// MARK: - Shared helpers

enum RemoteAPI {
    /// URLSession-with-delegate, configured to consult `RemoteHostTrust` on
    /// every server-trust challenge. Hosts the user has explicitly trusted
    /// pass through; everything else gets default OS validation.
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return URLSession(
            configuration: config,
            delegate: OptInTrustSessionDelegate(),
            delegateQueue: nil
        )
    }()

    /// Performs `request` and validates the HTTP status. Maps common failure
    /// codes to typed `PullRequestFetchError` cases. Returns body data on 2xx.
    static func send(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw PullRequestFetchError.network("non-HTTP response")
            }
            switch http.statusCode {
            case 200..<300: return data
            case 401:       throw PullRequestFetchError.unauthorized
            case 403:       throw PullRequestFetchError.forbidden
            case 404:       throw PullRequestFetchError.notFound
            default:
                let body = String(data: data, encoding: .utf8) ?? ""
                throw PullRequestFetchError.server(http.statusCode, body)
            }
        } catch let error as PullRequestFetchError {
            throw error
        } catch let urlError as URLError where Self.isTLSFailure(urlError) {
            throw PullRequestFetchError.tls(urlError.localizedDescription)
        } catch {
            throw PullRequestFetchError.network(error.localizedDescription)
        }
    }

    private static func isTLSFailure(_ error: URLError) -> Bool {
        switch error.code {
        case .secureConnectionFailed,
             .serverCertificateUntrusted,
             .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .clientCertificateRejected,
             .clientCertificateRequired:
            return true
        default:
            return false
        }
    }

    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// ISO-8601 parser tolerant to GitHub's no-fraction format.
    static func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        if let d = isoFormatter.date(from: raw) { return d }
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: raw)
    }
}
