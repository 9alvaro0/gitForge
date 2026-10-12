import Foundation
import Testing
@testable import gitForge

@Suite("GitCredentialInjection")
struct GitCredentialInjectionTests {
    static let credential = GitCredential(context: "https://example.test", username: "x-access-token",
                                          password: "test-secret-value-1")

    /// `git credential fill` for `host` with `credential`'s config and
    /// environment, and no global or system config (so no osxkeychain).
    private func credentialFill(host: String, credential: GitCredential) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + credential.configArguments + ["credential", "fill"]
        var environment = ProcessInfo.processInfo.environment
        environment.merge(credential.environment) { $1 }
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
        environment["GIT_CONFIG_NOSYSTEM"] = "1"
        environment.removeValue(forKey: "GIT_ASKPASS")
        environment.removeValue(forKey: "SSH_ASKPASS")
        process.environment = environment
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        input.fileHandleForWriting.write(Data("protocol=https\nhost=\(host)\n\n".utf8))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    @Test("Only HTTPS remotes get a context: scheme, host and port, lowercased, no userinfo",
          arguments: [
            ("https://github.com/octo/app.git", "https://github.com"),
            ("https://GitLab.Empresa.com:8443/group/sub/app.git", "https://gitlab.empresa.com:8443"),
            ("https://user:secret@github.com/octo/app", "https://github.com"),
          ])
    func httpsContext(url: String, expected: String) {
        #expect(GitCredentialInjection.context(forRemoteURL: url) == expected)
    }

    @Test("SSH, scp-style, plain HTTP and local remotes get none",
          arguments: ["git@github.com:octo/app.git", "ssh://git@github.com/octo/app.git",
                      "http://github.com/octo/app.git", "/Users/me/repos/app", "file:///tmp/app"])
    func noContext(url: String) {
        #expect(GitCredentialInjection.context(forRemoteURL: url) == nil)
    }

    @Test("Host and owner (first path segment) for the resolver")
    func hostAndOwner() {
        #expect(GitCredentialInjection.host(forRemoteURL: "https://GitLab.com/Group/Sub/app.git") == "gitlab.com")
        #expect(GitCredentialInjection.owner(forRemoteURL: "https://gitlab.com/Group/Sub/app.git") == "Group")
        #expect(GitCredentialInjection.owner(forRemoteURL: "https://github.com") == nil)
    }

    @Test("Usernames: x-access-token for GitHub, oauth2 for GitLab")
    func usernames() {
        #expect(GitCredentialInjection.username(for: .github) == "x-access-token")
        #expect(GitCredentialInjection.username(for: .gitlab) == "oauth2")
    }

    @Test("The token is only in the environment, never in the arguments")
    func argumentsAndEnvironment() {
        let credential = Self.credential
        #expect(credential.configArguments == [
            "-c", "credential.https://example.test.helper=",
            "-c", "credential.https://example.test.helper=\(GitCredential.helperScript)",
        ])
        #expect(!credential.configArguments.joined().contains("test-secret-value-1"))
        #expect(credential.environment == ["GITFORGE_CRED_USER": "x-access-token", "GITFORGE_CRED_PASS": "test-secret-value-1"])
    }

    @Test("Real git gets the credential for that host, and not for another one")
    func helperIsScoped() throws {
        let filled = try credentialFill(host: "example.test", credential: Self.credential)
        #expect(filled.contains("username=x-access-token"))
        #expect(filled.contains("password=test-secret-value-1"))
        let other = try credentialFill(host: "other.test", credential: Self.credential)
        #expect(!other.contains("test-secret-value-1"))
    }

    @Test("A refusal counts only when it's for the credential's own host")
    func rejectionForContext() {
        let context = "https://gitlab.com"
        #expect(GitCredentialInjection.isRejection(stderr: "fatal: Authentication failed for 'https://gitlab.com/group/app.git/'", context: context))
        #expect(!GitCredentialInjection.isRejection(stderr: "fatal: Authentication failed for 'https://other.test/x.git/'", context: context))
        #expect(!GitCredentialInjection.isRejection(stderr: "fatal: unable to access 'https://gitlab.com:8443/x.git/': The requested URL returned error: 401", context: context))
        #expect(GitCredentialInjection.isRejection(stderr: "remote: HTTP Basic: Access denied", context: context))
    }

    @Test("A refused credential (401) is told apart from a 403 or a network error")
    func rejection() {
        #expect(GitCredentialInjection.isRejection(stderr: "fatal: Authentication failed for 'https://github.com/octo/app.git/'"))
        #expect(GitCredentialInjection.isRejection(stderr: "remote: HTTP Basic: Access denied"))
        #expect(GitCredentialInjection.isRejection(stderr: "remote: Invalid username or token. Password authentication is not supported"))
        #expect(GitCredentialInjection.isRejection(stderr: "fatal: unable to access 'x': The requested URL returned error: 401"))
        #expect(!GitCredentialInjection.isRejection(stderr: "fatal: unable to access 'x': The requested URL returned error: 403"))
        #expect(!GitCredentialInjection.isRejection(stderr: "fatal: unable to access 'x': Could not resolve host: github.com"))
        #expect(GitCredentialInjection.isRejection(GitError.commandFailed(args: ["fetch"], exitCode: 128,
                                                                          stderr: "fatal: Authentication failed")))
        #expect(!GitCredentialInjection.isRejection(CancellationError()))
    }

    @Test("Printing, interpolating or dumping a credential never shows the token")
    func redactedDescription() {
        let credential = Self.credential
        var dumped = ""
        dump(credential, to: &dumped)
        for text in [String(describing: credential), "\(credential)", String(reflecting: credential), dumped] {
            #expect(!text.contains("test-secret-value-1"))
            #expect(text.contains("example.test"))
        }
    }
}
