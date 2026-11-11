import Foundation

/// What the repository's host says about one author's avatar (#65).
nonisolated enum AvatarLookupResult: Equatable, Sendable {
    /// The host's own avatar for the author.
    case found(URL)
    /// The host answered: no user of its own for that email, or a picture
    /// gitForge won't load (Gravatar, another site, the default placeholder).
    case none
    /// The host doesn't have the commit asked about (not pushed yet); another
    /// commit by the same author may work.
    case unknownCommit
}

/// Why a lookup gave no answer at all.
nonisolated enum AvatarLookupError: Error, Equatable, Sendable {
    /// The token was rejected (401): renew it once, then give up.
    case unauthorized
    /// Rate limited or not allowed (403, 429): back off for a while.
    case throttled
    /// Network, TLS, a 5xx or an answer that doesn't parse.
    case failed
}

/// The avatar a GitHub or GitLab host returns for a commit's author. Only the
/// host the repository's account signs in to is ever asked: never Gravatar,
/// which would hand email hashes to a third party ("no telemetry"). The
/// requests and the parsing are static so the tests feed them fixtures.
nonisolated struct HostAvatarLookup: Sendable {
    let http: HostingHTTP

    /// Pixel size asked for: twice the largest avatar the app draws (22 pt).
    static let pixelSize = 64

    init(http: HostingHTTP = .live) {
        self.http = http
    }

    /// The avatar of the author of `sha`, whose email is `email`.
    /// GitHub reads the commit (its author is the account the email belongs
    /// to); GitLab asks for the email's avatar, since its commits don't carry one.
    func avatar(email: String, sha: String, host: RemoteHost, token: String) async throws -> AvatarLookupResult {
        if let url = Self.gitHubNoreplyAvatar(email: email, host: host) { return .found(url) }
        guard let request = Self.request(email: email, sha: sha, host: host, token: token) else {
            throw AvatarLookupError.failed
        }
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await http.send(request)
        } catch HostingAuthError.cancelled {
            throw CancellationError()
        } catch {
            throw AvatarLookupError.failed
        }
        return try Self.parse(data, status: response.statusCode, sha: sha, host: host)
    }

    /// Downloads the picture at `url` (no token: avatars are public, and a
    /// token never goes to the CDN). `nil` when it isn't an image or is too
    /// large. A redirect off the hosts `isAllowed` accepts isn't followed
    /// (`AvatarRedirectGuard`), so it never reaches Gravatar or anyone else.
    func image(at url: URL, host: RemoteHost) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue("gitForge", forHTTPHeaderField: "User-Agent")
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        // The session's own delegate still answers certificate challenges
        // (pinned trust); this one only decides redirects for this request.
        guard let (data, response) = try? await http.session.data(for: request, delegate: AvatarRedirectGuard(host: host)),
              let http = response as? HTTPURLResponse else { return nil }
        return Self.acceptImage(data, response: http, host: host)
    }

    // MARK: Requests

    static func request(email: String, sha: String, host: RemoteHost, token: String) -> URLRequest? {
        switch host.provider {
        case .github:
            // The list endpoint from `sha`, one item: the commit itself
            // without the files and patches `/commits/{sha}` would carry.
            guard var components = URLComponents(string: "\(GitHubPullRequestProvider.base(for: host))/repos/\(host.slug)/commits") else {
                return nil
            }
            components.queryItems = [URLQueryItem(name: "sha", value: sha), URLQueryItem(name: "per_page", value: "1")]
            guard let url = components.url else { return nil }
            return GitHubPullRequestProvider.makeRequest(url: url, token: token)
        case .gitlab:
            guard var components = URLComponents(string: "\(GitLabPullRequestProvider.base(for: host))/avatar") else {
                return nil
            }
            components.queryItems = [URLQueryItem(name: "email", value: email),
                                     URLQueryItem(name: "size", value: String(pixelSize))]
            // `+` is a space in a query; an email can carry one.
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            guard let url = components.url else { return nil }
            return GitLabPullRequestProvider.makeRequest(url: url, token: token)
        }
    }

    // MARK: Responses

    static func parse(_ data: Data, status: Int, sha: String, host: RemoteHost) throws -> AvatarLookupResult {
        switch status {
        case 200..<300: break
        case 401: throw AvatarLookupError.unauthorized
        case 403, 429: throw AvatarLookupError.throttled
        // GitHub: 404 / 422 for a SHA it doesn't have, 409 for an empty repo.
        case 404, 409, 422: return host.provider == .github ? .unknownCommit : .none
        default: throw AvatarLookupError.failed
        }
        switch host.provider {
        case .github: return try parseGitHub(data, sha: sha, host: host)
        case .gitlab: return try parseGitLab(data, host: host)
        }
    }

    /// `[{ "sha": …, "author": { "avatar_url": … } | null }]`. `author` is
    /// null when the email isn't linked to an account.
    static func parseGitHub(_ data: Data, sha: String, host: RemoteHost) throws -> AvatarLookupResult {
        struct Item: Decodable {
            let sha: String
            let author: Author?
            struct Author: Decodable { let avatar_url: String? }
        }
        let items: [Item]
        do {
            items = try JSONDecoder().decode([Item].self, from: data)
        } catch {
            throw AvatarLookupError.failed
        }
        guard let first = items.first, first.sha.lowercased().hasPrefix(sha.lowercased()) else { return .unknownCommit }
        guard let raw = first.author?.avatar_url, let url = URL(string: raw) else { return .none }
        return accept(sized(url, provider: .github), host: host)
    }

    /// `{ "avatar_url": … }`; GitLab answers with Gravatar (or its own
    /// placeholder) when no user has that public email: both read as none.
    static func parseGitLab(_ data: Data, host: RemoteHost) throws -> AvatarLookupResult {
        struct Answer: Decodable { let avatar_url: String? }
        let answer: Answer
        do {
            answer = try JSONDecoder().decode(Answer.self, from: data)
        } catch {
            throw AvatarLookupError.failed
        }
        guard let raw = answer.avatar_url, let url = URL(string: raw, relativeTo: URL(string: "https://\(host.host)")) else {
            return .none
        }
        let absolute = url.absoluteURL
        if absolute.path.contains("no_avatar") { return .none }
        return accept(absolute, host: host)
    }

    private static func accept(_ url: URL, host: RemoteHost) -> AvatarLookupResult {
        isAllowed(url, for: host) ? .found(url) : .none
    }

    /// The image data, when the answer is a 2xx image of a sane size that
    /// ended on an allowed host.
    static func acceptImage(_ data: Data, response: HTTPURLResponse, host: RemoteHost) -> Data? {
        guard (200..<300).contains(response.statusCode),
              !data.isEmpty, data.count <= maxImageBytes,
              response.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("image/") ?? false
        else { return nil }
        if let final = response.url, !isAllowed(final, for: host) { return nil }
        return data
    }

    static let maxImageBytes = 512 * 1024

    // MARK: Policy

    /// Only the host itself, its subdomains (GitHub Enterprise's
    /// `avatars.<host>`), its API host, and GitHub.com's avatar CDN. Gravatar
    /// and every other site are refused, so an author's email (or its hash)
    /// never reaches a third party.
    static func isAllowed(_ url: URL, for host: RemoteHost) -> Bool {
        guard let urlHost = url.host?.lowercased() else { return false }
        let scheme = url.scheme?.lowercased()
        let instance = host.host.lowercased()
        let api = host.apiBaseURL
        let sameAsAPI = api?.host?.lowercased() == urlHost
        // Plain http only where the declared API itself is http (a lab instance).
        guard scheme == "https" || (scheme == "http" && sameAsAPI && api?.scheme?.lowercased() == "http") else {
            return false
        }
        if urlHost == instance || urlHost.hasSuffix(".\(instance)") || sameAsAPI { return true }
        return host.provider == .github && instance == "github.com" && urlHost == "avatars.githubusercontent.com"
    }

    /// GitHub serves avatars at any size through `s`; the default is 460 px.
    static func sized(_ url: URL, provider: RemoteProvider) -> URL {
        guard provider == .github, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = (components.queryItems ?? []).filter { $0.name != "s" }
        items.append(URLQueryItem(name: "s", value: String(pixelSize)))
        components.queryItems = items
        return components.url ?? url
    }

    /// `12345+login@users.noreply.github.com`, the address GitHub writes for
    /// users who keep their email private, names the account: its avatar
    /// needs no API call. github.com only.
    static func gitHubNoreplyAvatar(email: String, host: RemoteHost) -> URL? {
        guard host.provider == .github, host.host.lowercased() == "github.com" else { return nil }
        let lowered = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let suffix = "@users.noreply.github.com"
        guard lowered.hasSuffix(suffix) else { return nil }
        let local = lowered.dropLast(suffix.count)
        guard let plus = local.firstIndex(of: "+") else { return nil }
        let id = local[..<plus]
        guard !id.isEmpty, id.allSatisfy(\.isASCII), id.allSatisfy(\.isNumber) else { return nil }
        return URL(string: "https://avatars.githubusercontent.com/u/\(id)?s=\(pixelSize)")
    }
}

/// Follows an avatar download's redirect only to a host `HostAvatarLookup`
/// accepts, under the same rules as every other request (https only, no token
/// across hosts). A refused redirect returns the 3xx, which reads as "no picture".
nonisolated final class AvatarRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    let host: RemoteHost

    init(host: RemoteHost) {
        self.host = host
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(Self.redirect(request, from: task.originalRequest, host: host))
    }

    static func redirect(_ request: URLRequest, from original: URLRequest?, host: RemoteHost) -> URLRequest? {
        guard let target = request.url, HostAvatarLookup.isAllowed(target, for: host) else { return nil }
        return OptInTrustSessionDelegate.redirect(request, from: original)
    }
}
