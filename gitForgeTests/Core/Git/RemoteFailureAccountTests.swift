import Foundation
import Testing
@testable import gitForge

@Suite("RemoteFailure — account credential")
struct RemoteFailureAccountTests {
    @Test("GitHub's workflow-scope refusal names the scope", arguments: [
        " ! [remote rejected] main -> main (refusing to allow an OAuth App to create or update workflow `.github/workflows/ci.yml` without `workflow` scope)",
        " ! [remote rejected] main -> main (refusing to allow a Personal Access Token to create or update workflow `.github/workflows/ci.yml` without `workflow` scope)",
    ])
    func missingScope(stderr: String) {
        #expect(RemoteFailure(stderr: stderr) == .missingScope("workflow"))
    }

    @Test("The missing-scope message doesn't assume a gitForge account signed")
    func missingScopeMessage() {
        let message = RemoteFailure.missingScope("workflow").message
        #expect(message.contains("`workflow`"))
        #expect(message.contains("credential helper"))
        #expect(!message.contains("The account's token"))
    }

    @Test("A refused account credential says which account to reconnect")
    func accountRejected() {
        let failure = RemoteFailure.from(GitAccountError.rejected(account: "octo-test", host: "github.com"))
        #expect(failure == .accountRejected(account: "octo-test", host: "github.com"))
        #expect(failure.message.contains("octo-test"))
        #expect(failure.message.contains("Settings › Accounts"))
    }

    @Test("Getting the token offline or with a bad certificate keeps those categories")
    func tokenErrors() {
        #expect(RemoteFailure.from(HostingAuthError.network("offline")) == .network)
        #expect(RemoteFailure.from(HostingAuthError.tls("untrusted")) == .sslCertificate)
    }

    @Test("Raw stderr shown in a toast has account tokens blanked")
    func redactsOther() {
        SecretRedactor.shared.register("test-toast-token-1")
        let failure = RemoteFailure(stderr: "hook said test-toast-token-1 and failed")
        #expect(!failure.message.contains("test-toast-token-1"))
    }

    @Test("Cancelling is its own category, so no error toast is shown")
    func cancelled() {
        #expect(RemoteFailure.from(CancellationError()) == .cancelled)
    }

    @Test("A plain non-fast-forward rejection is still that")
    func plainRejection() {
        #expect(RemoteFailure(stderr: " ! [rejected] main -> main (non-fast-forward)") == .nonFastForward)
    }
}
