import Foundation
import Testing
@testable import gitForge

@Suite("RemoteFailure — stderr categorisation")
struct RemoteFailureCategorizationTests {

    @Test("SSL cert problem → .sslCertificate, not .authentication*")
    func sslCertificate() {
        let cases = [
            "SSL certificate problem: self signed certificate",
            "server certificate verification failed",
            "SSL_ERROR_SYSCALL",
            "certificate verify failed",
        ]
        for stderr in cases {
            #expect(RemoteFailure(stderr: stderr) == .sslCertificate, "missed: \(stderr)")
        }
    }

    @Test("SSH publickey/permission denied → .authenticationSSH")
    func sshAuth() {
        #expect(RemoteFailure(stderr: "git@github.com: Permission denied (publickey).") == .authenticationSSH)
        #expect(RemoteFailure(stderr: "Permission denied (publickey,gssapi-keyex,gssapi-with-mic).") == .authenticationSSH)
    }

    @Test("HTTPS 401/403/bad-credentials → .authenticationHTTPS")
    func httpsAuth() {
        #expect(RemoteFailure(stderr: "fatal: Authentication failed for 'https://github.com/...'") == .authenticationHTTPS)
        #expect(RemoteFailure(stderr: "remote: HTTP Basic: Access denied. The provided token has expired.") == .authenticationHTTPS)
        #expect(RemoteFailure(stderr: "fatal: unable to access ...: The requested URL returned error: 401") == .authenticationHTTPS)
        #expect(RemoteFailure(stderr: "fatal: unable to access ...: The requested URL returned error: 403 Forbidden") == .authenticationHTTPS)
    }

    @Test("GH006 / protected branch → .protectedBranch (NOT .nonFastForward)")
    func protectedBranch() {
        let stderr = """
        remote: error: GH006: Protected branch update failed for refs/heads/main.
        remote: error: Required status check "ci" is expected.
        """
        #expect(RemoteFailure(stderr: stderr) == .protectedBranch)
    }

    @Test("HTTP 429 → .rateLimited")
    func rateLimited() {
        #expect(RemoteFailure(stderr: "fatal: unable to access ...: The requested URL returned error: 429") == .rateLimited)
        #expect(RemoteFailure(stderr: "remote: API rate limit exceeded for token") == .rateLimited)
    }

    @Test("HTTP 502/503/504 → .serverUnavailable")
    func serverUnavailable() {
        #expect(RemoteFailure(stderr: "fatal: unable to access ...: The requested URL returned error: 502") == .serverUnavailable)
        #expect(RemoteFailure(stderr: "fatal: unable to access ...: The requested URL returned error: 503") == .serverUnavailable)
        #expect(RemoteFailure(stderr: "fatal: unable to access ...: The requested URL returned error: 504") == .serverUnavailable)
        #expect(RemoteFailure(stderr: "fatal: Bad gateway") == .serverUnavailable)
    }

    @Test("DNS / connection failures still categorised as .network")
    func network() {
        #expect(RemoteFailure(stderr: "fatal: unable to access ...: Could not resolve host: github.com") == .network)
        #expect(RemoteFailure(stderr: "fatal: unable to access ...: Connection refused") == .network)
    }

    @Test("Non-fast-forward (without protected-branch markers) still categorised as .nonFastForward")
    func nonFastForward() {
        let stderr = """
         ! [rejected]        main -> main (non-fast-forward)
        error: failed to push some refs to 'origin'
        """
        #expect(RemoteFailure(stderr: stderr) == .nonFastForward)
    }

    @Test("Divergent branches → .divergentBranches")
    func divergent() {
        let stderr = """
        hint: You have divergent branches and need to specify how to reconcile them.
        """
        #expect(RemoteFailure(stderr: stderr) == .divergentBranches)
    }

    @Test("Unrecognised text falls to .other (carrying the raw stderr)")
    func otherFallback() {
        let stderr = "some entirely new git error nobody has seen before"
        if case .other(let raw) = RemoteFailure(stderr: stderr) {
            #expect(raw == stderr)
        } else {
            Issue.record("Expected .other, got something else")
        }
    }

    @Test("Every kind has a non-empty title + message")
    func everyKindHasCopy() {
        let kinds: [RemoteFailure] = [
            .authenticationHTTPS, .authenticationSSH, .nonFastForward,
            .divergentBranches, .conflict, .network, .sslCertificate,
            .protectedBranch, .serverUnavailable, .rateLimited, .noUpstream,
            .other("x"),
        ]
        for kind in kinds {
            #expect(!kind.title.isEmpty)
            #expect(!kind.message.isEmpty)
        }
    }
}
