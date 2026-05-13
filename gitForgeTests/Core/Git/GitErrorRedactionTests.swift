import Foundation
import Testing
@testable import gitForge

@Suite("GitError — redaction")
struct GitErrorRedactionTests {

    @Test("Redacts userinfo from args of a commandFailed errorDescription")
    func redactsTokenInArgs() {
        let error = GitError.commandFailed(
            args: ["clone", "https://oauth2:SECRET_TOKEN@github.com/user/repo.git"],
            exitCode: 128,
            stderr: ""
        )
        let description = error.errorDescription ?? ""
        #expect(description.contains("SECRET_TOKEN") == false)
        #expect(description.contains("oauth2:") == false)
        #expect(description.contains("://****@"))
    }

    @Test("Redacts userinfo from stderr of a commandFailed errorDescription")
    func redactsTokenInStderr() {
        let error = GitError.commandFailed(
            args: ["clone", "host"],
            exitCode: 128,
            stderr: "fatal: unable to access 'https://oauth2:SECRET@github.com/...': not found"
        )
        let description = error.errorDescription ?? ""
        #expect(description.contains("SECRET") == false)
        #expect(description.contains("oauth2:") == false)
        #expect(description.contains("://****@"))
    }

    @Test("Leaves SCP-style SSH URLs untouched (no credentials embedded)")
    func leavesSshAlone() {
        let error = GitError.commandFailed(
            args: ["fetch", "git@github.com:user/repo.git"],
            exitCode: 1,
            stderr: ""
        )
        let description = error.errorDescription ?? ""
        // SCP form `user@host:path` is not a credential carrier — keep it
        // readable so the user can debug.
        #expect(description.contains("git@github.com"))
        #expect(description.contains("****") == false)
    }

    @Test("Plain URL without userinfo passes through unchanged")
    func plainUrlUntouched() {
        let error = GitError.commandFailed(
            args: ["clone", "https://github.com/user/repo.git"],
            exitCode: 128,
            stderr: ""
        )
        let description = error.errorDescription ?? ""
        #expect(description.contains("https://github.com/user/repo.git"))
        #expect(description.contains("****") == false)
    }

    @Test("Multiple userinfo URLs in stderr are all redacted")
    func multipleUrlsRedacted() {
        let error = GitError.commandFailed(
            args: [],
            exitCode: 1,
            stderr: "tried https://a:1@x.com and https://b:2@y.com, both failed"
        )
        let description = error.errorDescription ?? ""
        #expect(description.contains("a:1") == false)
        #expect(description.contains("b:2") == false)
        #expect(description.contains(":1@") == false)
        #expect(description.contains(":2@") == false)
    }

    @Test("Error message keeps the exit code and the rest of stderr context")
    func preservesContext() {
        let error = GitError.commandFailed(
            args: ["clone", "https://x:y@host/r.git"],
            exitCode: 128,
            stderr: "fatal: repository not found"
        )
        let description = error.errorDescription ?? ""
        #expect(description.contains("128"))
        #expect(description.contains("repository not found"))
    }
}
