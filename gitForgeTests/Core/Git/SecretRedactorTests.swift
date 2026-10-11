import Foundation
import Testing
@testable import gitForge

@Suite("SecretRedactor")
struct SecretRedactorTests {
    @Test("Registered tokens are blanked in git logs and errors")
    func redactsRegistered() {
        SecretRedactor.shared.register("test-redaction-token-1")
        #expect(GitCLI.redacted("remote: echo test-redaction-token-1 here") == "remote: echo **** here")
        let error = GitError.commandFailed(args: ["push"], exitCode: 1, stderr: "hook said test-redaction-token-1")
        #expect(!(error.errorDescription ?? "").contains("test-redaction-token-1"))
    }

    @Test("URL userinfo is still blanked, with or without registered tokens")
    func keepsURLRedaction() {
        #expect(GitCLI.redacted("fatal: https://oauth2:abc@gitlab.com/x") == "fatal: https://****@gitlab.com/x")
    }

    @Test("Short values aren't registered: blanking them would mangle ordinary text")
    func ignoresShort() {
        SecretRedactor.shared.register("main")
        #expect(GitCLI.redacted("push origin main") == "push origin main")
    }
}
