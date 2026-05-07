import Foundation
import os

/// Server-trust challenge handler that overrides the OS verdict only for
/// hosts the user has explicitly added via `RemoteHostTrust`. Every other
/// host falls back to default macOS validation.
final class OptInTrustSessionDelegate: NSObject, URLSessionDelegate {
    private static let logger = Logger(subsystem: "com.warwarelabs.gitForge", category: "trust-delegate")

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

        let host = challenge.protectionSpace.host
        guard RemoteHostTrust.shared.isTrusted(host) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        Self.logger.info("Accepting self-signed cert for trusted host \(host, privacy: .public)")
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
