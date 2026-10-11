import Foundation

/// HTTP for the account endpoints. The app uses `live`, with the same trust
/// and redirect rules as `RemoteAPI.session` (certificates pinned through
/// `RemoteHostTrust`; a token never follows a redirect to another host).
/// Tests pass a session that answers from fixtures.
nonisolated struct HostingHTTP: Sendable {
    let session: URLSession

    static let live: HostingHTTP = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        return HostingHTTP(session: URLSession(configuration: config, delegate: OptInTrustSessionDelegate(), delegateQueue: nil))
    }()

    /// Sends `request`; transport failures become `HostingAuthError`. The
    /// status isn't checked here.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw HostingAuthError.network("non-HTTP response") }
            return (data, http)
        } catch let error as HostingAuthError {
            throw error
        } catch is CancellationError {
            throw HostingAuthError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw HostingAuthError.cancelled
        } catch let error as URLError where Self.isTLSFailure(error) {
            throw HostingAuthError.tls(error.localizedDescription)
        } catch {
            throw HostingAuthError.network(error.localizedDescription)
        }
    }

    /// GET with the token as a bearer; non-2xx statuses throw.
    func get(_ url: URL, token: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("gitForge", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await send(request)
        if response.statusCode == 403, Self.isInsufficientScope(data, response) { throw HostingAuthError.forbidden }
        try Self.check(response.statusCode)
        return (data, response)
    }

    /// Form-encoded POST to an OAuth endpoint. The status isn't checked:
    /// OAuth errors come back in the body.
    func postForm(_ url: URL, _ fields: [(String, String)]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("gitForge", forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(Self.formEncode(fields).utf8)
        return try await send(request)
    }

    static func check(_ status: Int) throws {
        switch status {
        case 200..<300: return
        case 401: throw HostingAuthError.unauthorized
        // A bare 403 says nothing about the token: a WAF, a load balancer off
        // VPN or GitHub's rate limit answer it too. Only GitLab's
        // `insufficient_scope` (see `get`) becomes `.forbidden`.
        default: throw HostingAuthError.server(status)
        }
    }

    /// GitLab's answer for a token whose scopes don't allow the call.
    static func isInsufficientScope(_ data: Data, _ response: HTTPURLResponse) -> Bool {
        if response.value(forHTTPHeaderField: "WWW-Authenticate")?.contains("insufficient_scope") == true { return true }
        return OAuthResponse.errorCode(data) == "insufficient_scope"
    }

    static func formEncode(_ fields: [(String, String)]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields
            .map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.1)" }
            .joined(separator: "&")
    }

    static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw HostingAuthError.decoding(String(describing: type))
        }
    }

    private static func isTLSFailure(_ error: URLError) -> Bool {
        switch error.code {
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
             .clientCertificateRejected, .clientCertificateRequired:
            true
        default:
            false
        }
    }
}
