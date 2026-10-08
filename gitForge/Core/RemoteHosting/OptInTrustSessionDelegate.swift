import Foundation
import os

/// Delegate for `RemoteAPI.session`, the only session that carries tokens.
///
/// - Server trust: hosts macOS trusts get normal validation; otherwise only a
///   certificate the user pinned through `RemoteHostTrust` is accepted.
/// - Redirects: never followed to plain `http`, and the token headers are
///   stripped whenever a redirect leaves the original host, so a token can
///   only ever reach the host it was issued for.
///
/// `nonisolated`: URLSession invokes these callbacks on its delegate queue,
/// never on the main actor.
nonisolated final class OptInTrustSessionDelegate: NSObject, URLSessionTaskDelegate {
    private static let logger = Logger(subsystem: "com.warwarelabs.gitForge", category: "trust-delegate")

    /// Headers that carry a remote-host token (GitHub / GitLab).
    static let credentialHeaders = ["Authorization", "PRIVATE-TOKEN"]

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        switch RemoteHostTrust.shared.decision(for: challenge.protectionSpace.host, trust: trust) {
        case .systemDefault:
            completionHandler(.performDefaultHandling, nil)
        case .accept:
            completionHandler(.useCredential, URLCredential(trust: trust))
        case .reject:
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let next = Self.redirect(request, from: task.originalRequest)
        if next == nil {
            Self.logger.error("Refused insecure redirect to \(request.url?.absoluteString ?? "?", privacy: .public)")
        }
        completionHandler(next)
    }

    /// Pure redirect policy: `nil` refuses the redirect (the 3xx response is
    /// returned to the caller instead).
    static func redirect(_ request: URLRequest, from original: URLRequest?) -> URLRequest? {
        guard let target = request.url, target.scheme?.lowercased() == "https" else { return nil }
        let originalHost = original?.url?.host?.lowercased()
        guard originalHost != target.host?.lowercased() else { return request }
        var stripped = request
        for header in credentialHeaders {
            stripped.setValue(nil, forHTTPHeaderField: header)
        }
        return stripped
    }
}
