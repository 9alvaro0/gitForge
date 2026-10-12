import Foundation
import Testing
@testable import gitForge

@Suite("GitProcess — account credential")
struct GitProcessCredentialTests {
    static let credential = GitCredential(context: "https://example.test", username: "oauth2",
                                          password: "test-secret-value-2")

    @Test("The credential's -c pairs go before the subcommand; the token only in the environment")
    func makeWithCredential() {
        let process = GitProcess.make(arguments: ["fetch", "--all"], workingDirectory: FileManager.default.temporaryDirectory,
                                      credential: Self.credential)
        #expect(process.arguments == ["git", "-c", "core.quotePath=false", "-c", "core.precomposeUnicode=true",
                                      "-c", "diff.suppressBlankEmpty=false"]
                + Self.credential.configArguments + ["fetch", "--all"])
        #expect(process.environment?["GITFORGE_CRED_USER"] == "oauth2")
        #expect(process.environment?["GITFORGE_CRED_PASS"] == "test-secret-value-2")
        #expect(!(process.arguments ?? []).joined().contains("test-secret-value-2"))
    }

    @Test("Without a credential nothing is added")
    func makeWithout() {
        let process = GitProcess.make(arguments: ["fetch"], workingDirectory: FileManager.default.temporaryDirectory)
        #expect(process.arguments == ["git", "-c", "core.quotePath=false", "-c", "core.precomposeUnicode=true",
                                      "-c", "diff.suppressBlankEmpty=false", "fetch"])
        #expect(process.environment?["GITFORGE_CRED_PASS"] == nil)
    }

    @Test("GitCLI.run hands git the helper config and registers the token for redaction")
    func runPassesCredential() async throws {
        let repo = try GitTestRepo()
        defer { repo.remove() }
        let result = try await repo.cli.run(["config", "--get-all", "credential.https://example.test.helper"],
                                            credential: Self.credential)
        #expect(result.stdout == "\n\(GitCredential.helperScript)\n")
        #expect(GitCLI.redacted("echo test-secret-value-2") == "echo ****")
    }
}
