import CryptoKit
import Foundation
import Security
import os

/// Certificates the user accepted for hosts macOS doesn't trust (typical
/// corporate / self-hosted GitLab with a private CA). Only affects requests
/// made through `RemoteAPI`; git itself keeps its own TLS settings.
///
/// Trust is **pinned**: the user accepts one specific certificate (shown as
/// a SHA-256 fingerprint before confirming), and only that certificate is
/// accepted afterwards. The previous model trusted *any* certificate for a
/// trusted host, so a network attacker able to spoof DNS for it (hostile
/// Wi-Fi) could intercept API requests — and the token they carry.
///
/// Hosts trusted under the old model (stored without a fingerprint) are
/// migrated trust-on-first-use: the next certificate they present is pinned.
///
/// Stored in `UserDefaults`, keyed by lowercased host. Fingerprints aren't
/// secrets; a same-user process that can rewrite our defaults can already do
/// far worse, so the threat this addresses is the network, not the machine.
nonisolated struct RemoteHostTrust: Sendable {
    static let shared = RemoteHostTrust()
    private static let logger = Logger(subsystem: "com.warwarelabs.gitForge", category: "trust")

    private static let pinsKey = "com.warwarelabs.gitForge.trustedCertificates"
    /// Pre-pinning list of bare host names.
    private static let legacyKey = "com.warwarelabs.gitForge.trustedHosts"

    /// `nil` = standard defaults; tests pass a throwaway suite.
    private let suiteName: String?

    init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    // MARK: Queries

    /// Hosts with a pinned certificate or a legacy (unpinned) trust entry.
    func trustedHosts() -> [String] {
        Array(Set(pins().keys).union(legacyHosts())).sorted()
    }

    func isTrusted(_ host: String) -> Bool {
        let host = host.lowercased()
        return pins()[host] != nil || legacyHosts().contains(host)
    }

    func pinnedFingerprint(for host: String) -> String? {
        pins()[host.lowercased()]
    }

    // MARK: Mutations

    /// Accept exactly the certificate with `fingerprint` for `host`.
    func trust(_ host: String, fingerprint: String) {
        let host = host.lowercased()
        var pins = pins()
        pins[host] = fingerprint
        defaults.set(pins, forKey: Self.pinsKey)
        removeLegacy(host)
        Self.logger.info("Pinned certificate for \(host, privacy: .public)")
    }

    func revoke(_ host: String) {
        let host = host.lowercased()
        var pins = pins()
        pins.removeValue(forKey: host)
        defaults.set(pins, forKey: Self.pinsKey)
        removeLegacy(host)
        Self.logger.info("Revoked trust for \(host, privacy: .public)")
    }

    // MARK: Challenge decision

    enum Decision: Equatable {
        /// Let URLSession apply the normal OS validation.
        case systemDefault
        /// Accept the presented certificate. `pin` is set when a legacy
        /// (unpinned) entry is being migrated on first use.
        case accept(pin: String?)
        /// The certificate doesn't match the pin: refuse the connection.
        case reject
    }

    /// Pure decision table, separated from `SecTrust` so it can be tested.
    static func decide(systemTrusted: Bool,
                       presentedFingerprint: String?,
                       pinned: String?,
                       legacyTrusted: Bool) -> Decision {
        // A certificate macOS trusts never needs the pin (e.g. the host moved
        // to a public CA).
        if systemTrusted { return .systemDefault }
        guard let presentedFingerprint else { return .systemDefault }
        if let pinned {
            return pinned == presentedFingerprint ? .accept(pin: nil) : .reject
        }
        if legacyTrusted { return .accept(pin: presentedFingerprint) }
        return .systemDefault
    }

    /// Applies `decide` to a live server-trust challenge.
    func decision(for host: String, trust: SecTrust) -> Decision {
        let systemTrusted = SecTrustEvaluateWithError(trust, nil)
        let decision = Self.decide(systemTrusted: systemTrusted,
                                   presentedFingerprint: Self.fingerprint(of: trust),
                                   pinned: pinnedFingerprint(for: host),
                                   legacyTrusted: legacyHosts().contains(host.lowercased()))
        if case .accept(let pin?) = decision {
            // `self.`: the `trust` parameter shadows the method.
            self.trust(host, fingerprint: pin)
        }
        if decision == .reject {
            Self.logger.error("Certificate for \(host, privacy: .public) doesn't match the pinned fingerprint — refusing")
        }
        return decision
    }

    // MARK: Fingerprints

    /// SHA-256 of the leaf certificate's DER bytes, as colon-separated
    /// uppercase hex (the format Keychain Access and browsers display).
    static func fingerprint(of trust: SecTrust) -> String? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else { return nil }
        return fingerprint(ofCertificateData: SecCertificateCopyData(leaf) as Data)
    }

    static func fingerprint(ofCertificateData data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    /// Connects to `https://<host>/` just far enough to read the certificate
    /// it presents, without sending anything. Used to show the user what
    /// they're about to trust. Returns nil if no TLS handshake happened.
    static func presentedFingerprint(host: String) async -> String? {
        guard let url = URL(string: "https://\(host)/") else { return nil }
        let probe = CertificateProbe()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: config, delegate: probe, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        _ = try? await session.data(from: url)
        return probe.fingerprint
    }

    // MARK: Storage

    private func pins() -> [String: String] {
        defaults.dictionary(forKey: Self.pinsKey) as? [String: String] ?? [:]
    }

    private func legacyHosts() -> [String] {
        defaults.stringArray(forKey: Self.legacyKey) ?? []
    }

    private func removeLegacy(_ host: String) {
        let remaining = legacyHosts().filter { $0 != host }
        defaults.set(remaining, forKey: Self.legacyKey)
    }
}

/// Records the leaf fingerprint of the first server-trust challenge, then
/// cancels it so no request is ever sent to an unverified server.
private nonisolated final class CertificateProbe: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var captured: String?

    var fingerprint: String? {
        lock.lock(); defer { lock.unlock() }
        return captured
    }

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            let value = RemoteHostTrust.fingerprint(of: trust)
            lock.lock(); captured = value; lock.unlock()
        }
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}
