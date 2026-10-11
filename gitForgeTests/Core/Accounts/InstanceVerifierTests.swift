import Foundation
import Testing
@testable import gitForge

@Suite("InstanceVerifier")
struct InstanceVerifierTests {
    let server = StubServer()

    private func instance(_ kind: HostingInstance.Kind) -> HostingInstance {
        HostingInstance(kind: kind, host: server.host)
    }

    @Test("GitHub Enterprise answering /meta is verified, with device flow")
    func gitHubMeta() async {
        server.on("GET", "/api/v3/meta", fixture: "github-meta")
        #expect(await InstanceVerifier(http: server.http).verify(instance(.github)) == .verified(deviceFlow: true))
        #expect(server.requests("GET", "/api/v3/meta").first?.header("Authorization") == nil)
    }

    @Test("GitLab 17.2 or later has device flow; older doesn't")
    func gitLabVersions() async {
        server.on("GET", "/api/v4/version", fixture: "gitlab-version")
        #expect(await InstanceVerifier(http: server.http).verify(instance(.gitlab)) == .verified(deviceFlow: true))
        let old = StubServer()
        old.on("GET", "/api/v4/version", fixture: "gitlab-version-old")
        #expect(await InstanceVerifier(http: old.http).verify(HostingInstance(kind: .gitlab, host: old.host))
                == .verified(deviceFlow: false))
    }

    @Test("401 means it needs a token: saved and checked at the first sign-in")
    func needsSignIn() async {
        server.on("GET", "/api/v4/version", status: 401, body: Data(#"{"message":"401 Unauthorized"}"#.utf8))
        #expect(await InstanceVerifier(http: server.http).verify(instance(.gitlab)) == .needsSignIn)
    }

    @Test("No API at that address: unreachable, with the status")
    func notFound() async {
        server.on("GET", "/api/v4/version", status: 404, body: Data("<html>".utf8))
        guard case .unreachable(let message) = await InstanceVerifier(http: server.http).verify(instance(.gitlab)) else {
            Issue.record("expected unreachable"); return
        }
        #expect(message.contains("404"))
    }

    @Test("An untrusted certificate asks to trust it")
    func untrusted() async {
        server.fail("GET", "/api/v4/version", with: .serverCertificateUntrusted)
        #expect(await InstanceVerifier(http: server.http).verify(instance(.gitlab)) == .untrustedCertificate)
    }

    @Test("Version parsing", arguments: [("17.2.0", true), ("17.10.1-ee", true), ("18.0.0", true), ("17.1.9", false), ("16.11.3", false), ("garbage", false)])
    func versions(version: String, expected: Bool) {
        #expect(InstanceVerifier.supportsDeviceFlow(version) == expected)
    }
}
