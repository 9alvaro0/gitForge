import Foundation
import Testing
@testable import gitForge

@Suite("RemoteHostTrust — pinning decision")
struct RemoteHostTrustDecisionTests {

    @Test("A certificate macOS trusts always uses the system default")
    func systemTrustedWins() {
        #expect(RemoteHostTrust.decide(systemTrusted: true, presentedFingerprint: "AA", pinned: "BB", legacyTrusted: false) == .systemDefault)
    }

    @Test("Untrusted certificate matching the pin is accepted")
    func pinMatch() {
        #expect(RemoteHostTrust.decide(systemTrusted: false, presentedFingerprint: "AA", pinned: "AA", legacyTrusted: false) == .accept(pin: nil))
    }

    @Test("Untrusted certificate NOT matching the pin is rejected (MITM)")
    func pinMismatch() {
        #expect(RemoteHostTrust.decide(systemTrusted: false, presentedFingerprint: "EVIL", pinned: "AA", legacyTrusted: false) == .reject)
    }

    @Test("Legacy trusted host pins the first certificate it presents")
    func legacyMigratesOnFirstUse() {
        #expect(RemoteHostTrust.decide(systemTrusted: false, presentedFingerprint: "AA", pinned: nil, legacyTrusted: true) == .accept(pin: "AA"))
    }

    @Test("Unknown untrusted host falls back to the system (which refuses)")
    func unknownHost() {
        #expect(RemoteHostTrust.decide(systemTrusted: false, presentedFingerprint: "AA", pinned: nil, legacyTrusted: false) == .systemDefault)
    }

    @Test("Fingerprints are colon-separated uppercase SHA-256 hex")
    func fingerprintFormat() {
        let fingerprint = RemoteHostTrust.fingerprint(ofCertificateData: Data("abc".utf8))
        #expect(fingerprint == "BA:78:16:BF:8F:01:CF:EA:41:41:40:DE:5D:AE:22:23:B0:03:61:A3:96:17:7A:9C:B4:10:FF:61:F2:00:15:AD")
    }
}

@Suite("RemoteHostTrust — storage", .serialized)
struct RemoteHostTrustStorageTests {

    private func withSuite(_ body: (RemoteHostTrust, UserDefaults) throws -> Void) rethrows {
        let name = "gitForge-trust-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(RemoteHostTrust(suiteName: name), defaults)
    }

    @Test("trust pins a fingerprint; revoke removes it; hosts are case-insensitive")
    func trustAndRevoke() {
        withSuite { trust, _ in
            trust.trust("GitLab.Example.org", fingerprint: "AA:BB")
            #expect(trust.isTrusted("gitlab.example.org"))
            #expect(trust.pinnedFingerprint(for: "gitlab.example.org") == "AA:BB")
            trust.revoke("gitlab.example.org")
            #expect(!trust.isTrusted("gitlab.example.org"))
        }
    }

    @Test("Legacy entries stay trusted until pinned, then leave the legacy list")
    func legacyMigration() {
        withSuite { trust, defaults in
            defaults.set(["gitlab.corp"], forKey: "com.warwarelabs.gitForge.trustedHosts")
            #expect(trust.isTrusted("gitlab.corp"))
            #expect(trust.pinnedFingerprint(for: "gitlab.corp") == nil)
            trust.trust("gitlab.corp", fingerprint: "CC")
            #expect(defaults.stringArray(forKey: "com.warwarelabs.gitForge.trustedHosts") == [])
            #expect(trust.trustedHosts() == ["gitlab.corp"])
        }
    }
}

@Suite("OptInTrustSessionDelegate — redirect policy")
struct RedirectPolicyTests {

    private func request(_ url: String, token: Bool = true) -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        if token {
            request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
            request.setValue("secret", forHTTPHeaderField: "PRIVATE-TOKEN")
        }
        return request
    }

    @Test("Same-host redirect keeps the credentials")
    func sameHost() throws {
        let next = try #require(OptInTrustSessionDelegate.redirect(request("https://api.github.com/b"),
                                                                    from: request("https://api.github.com/a")))
        #expect(next.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
    }

    @Test("Cross-host redirect strips every token header")
    func crossHost() throws {
        let next = try #require(OptInTrustSessionDelegate.redirect(request("https://evil.example/x"),
                                                                    from: request("https://api.github.com/a")))
        #expect(next.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(next.value(forHTTPHeaderField: "PRIVATE-TOKEN") == nil)
    }

    @Test("Redirects to plain http are refused")
    func downgrade() {
        #expect(OptInTrustSessionDelegate.redirect(request("http://api.github.com/a"),
                                                   from: request("https://api.github.com/a")) == nil)
    }
}
