import Foundation
import Testing
@testable import gitForge

/// Hands every remote the same credential (or none), like an account would.
private struct StaticCredentials: GitCredentialProvider {
    let credential: GitCredential?

    func signer(remoteURL: String, remoteName: String, repoPath: String) async -> GitSigner {
        credential?.accountId.map(GitSigner.account) ?? .none
    }

    func withCredential<T: Sendable>(remoteURL: String, remoteName: String, repoPath: String,
                                     _ operation: @Sendable (GitCredential?) async throws -> T) async throws -> T {
        try await operation(credential)
    }
}

@Suite("Git over HTTP with an account's credential (local smart-HTTP server)", .serialized)
struct GitCredentialIntegrationTests {
    static let user = "x-access-token"
    static let token = "test-integration-token-1"

    /// A server with `app.git` holding one commit (README.md) on main.
    private func makeServer() async throws -> GitHTTPTestServer {
        let server = try GitHTTPTestServer(username: Self.user, password: Self.token)
        try await server.start()
        let bare = try await server.makeBareRepo("app.git")
        let seed = try await GitTestRepo.make { seed in
            try seed.commit("first", files: ["README.md": "hello\n"])
            try seed.git("push", "-q", bare.path, "main")
        }
        defer { seed.remove() }
        return server
    }

    private func credential(_ server: GitHTTPTestServer, password: String = token) -> GitCredential {
        // The server is plain HTTP on loopback: tests build the context
        // directly (the app only ever builds HTTPS ones).
        GitCredential(context: server.baseURL, username: Self.user, password: password, accountId: UUID())
    }

    private func workRepo(_ server: GitHTTPTestServer) async throws -> GitTestRepo {
        let remote = server.url("app.git")
        return try await GitTestRepo.make { work in
            try work.git("remote", "add", "origin", remote)
        }
    }

    @Test("fetch and push go with the account's credential")
    func fetchAndPush() async throws {
        let server = try await makeServer()
        defer { server.stop() }
        let work = try await workRepo(server)
        defer { work.remove() }
        let cli = GitCLI(workingDirectory: work.url, credentials: StaticCredentials(credential: credential(server)))

        try await cli.fetchAll()
        let sha = try await work.perform { work in
            try work.git("checkout", "-q", "-B", "main", "origin/main")
            return try work.commit("second", files: ["a.txt": "a\n"])
        }
        try await cli.push(setUpstream: true, remote: "origin", branch: "main")

        let remoteHead = try await work.gitAsync("ls-remote", server.root.appendingPathComponent("app.git").path,
                                                 "refs/heads/main")
        #expect(remoteHead.hasPrefix(sha))
        let expected = "Basic " + Data("\(Self.user):\(Self.token)".utf8).base64EncodedString()
        #expect(server.authorizations.contains(expected))
    }

    @Test("A wrong token fails as a refused credential, and the token isn't in the message")
    func wrongToken() async throws {
        let server = try await makeServer()
        defer { server.stop() }
        let work = try await workRepo(server)
        defer { work.remove() }
        let cli = GitCLI(workingDirectory: work.url,
                         credentials: StaticCredentials(credential: credential(server, password: "test-wrong-token-1")))
        let thrown = await #expect(throws: GitError.self) { try await cli.fetchAll() }
        let error = try #require(thrown)
        #expect(GitCredentialInjection.isRejection(error))
        #expect(RemoteFailure.from(error) == .authenticationHTTPS)
        #expect(!(error.errorDescription ?? "").contains("test-wrong-token-1"))
    }

    @Test("A remote without an account: gitForge sends git no credential")
    func noAccount() async throws {
        let server = try await makeServer()
        defer { server.stop() }
        let work = try await workRepo(server)
        defer { work.remove() }
        // An empty helper resets the list: the developer's own helpers
        // (osxkeychain, a GUI one like GCM) are never asked.
        try await work.gitAsync("config", "credential.helper", "")
        let cli = GitCLI(workingDirectory: work.url, credentials: StaticCredentials(credential: nil))
        await #expect(throws: GitError.self) { try await cli.fetchAll() }
        #expect(!server.authorizations.isEmpty)
        #expect(server.authorizations.allSatisfy { $0 == nil })
    }

    @Test("clone goes with the account's credential")
    func cloneWithCredential() async throws {
        let server = try await makeServer()
        defer { server.stop() }
        let destination = TemporaryDirectories.make("gitForge-clone")
        defer { try? FileManager.default.removeItem(at: destination) }
        try await GitCLI.clone(url: server.url("app.git"), destination: destination,
                               credentials: StaticCredentials(credential: credential(server)))
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("README.md").path))
    }

    @Test("A shallow clone fetches only the latest commit")
    func shallowClone() async throws {
        let server = try await makeServer()
        defer { server.stop() }
        let bare = try await server.makeBareRepo("deep.git")
        let seed = try await GitTestRepo.make { seed in
            try seed.commit("one", files: ["f.txt": "1\n"])
            try seed.commit("two", files: ["f.txt": "2\n"])
            try seed.git("push", "-q", bare.path, "main")
        }
        defer { seed.remove() }
        let destination = TemporaryDirectories.make("gitForge-clone")
        defer { try? FileManager.default.removeItem(at: destination) }

        try await GitCLI.clone(url: server.url("deep.git"), destination: destination,
                               options: CloneOptions(shallow: true),
                               credentials: StaticCredentials(credential: credential(server)))

        let cloned = GitCLI(workingDirectory: destination)
        let count = try await cloned.run(["rev-list", "--count", "HEAD"]).stdout
        #expect(count.trimmingCharacters(in: .whitespacesAndNewlines) == "1")
    }
}
