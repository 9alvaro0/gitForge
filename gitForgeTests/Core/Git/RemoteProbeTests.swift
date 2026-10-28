import Foundation
import Testing
@testable import gitForge

/// Hands every remote the same credential (or none), like an account would.
private struct FixedCredentials: GitCredentialProvider {
    let credential: GitCredential?

    func signer(remoteURL: String, remoteName: String, repoPath: String) async -> GitSigner {
        credential?.accountId.map(GitSigner.account) ?? .none
    }

    func withCredential<T: Sendable>(remoteURL: String, remoteName: String, repoPath: String,
                                     _ operation: @Sendable (GitCredential?) async throws -> T) async throws -> T {
        try await operation(credential)
    }
}

@Suite("RemoteProbe", .serialized)
struct RemoteProbeTests {
    static let user = "x-access-token"
    static let token = "test-probe-token-1"

    @Test("The default branch is read from ls-remote --symref")
    func parse() {
        #expect(RemoteProbe.parse(lsRemoteOutput: "ref: refs/heads/main\tHEAD\nabc123\tHEAD\n") == "main")
        #expect(RemoteProbe.parse(lsRemoteOutput: "abc123\tHEAD\n") == nil)
    }

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

    private func credentials(_ server: GitHTTPTestServer, password: String = token) -> FixedCredentials {
        FixedCredentials(credential: GitCredential(context: server.baseURL, username: Self.user,
                                                   password: password, accountId: UUID()))
    }

    @Test("With the right credential the repo is reachable")
    func reachable() async throws {
        let server = try await makeServer()
        defer { server.stop() }
        let result = await RemoteProbe.run(url: server.url("app.git"), credentials: credentials(server))
        guard case .reachable = result else {
            Issue.record("expected reachable, got \(result)")
            return
        }
    }

    @Test("A wrong token or a missing repo is unreachable, with the reason")
    func unreachable() async throws {
        let server = try await makeServer()
        defer { server.stop() }
        let wrong = await RemoteProbe.run(url: server.url("app.git"), credentials: credentials(server, password: "test-wrong-1"))
        #expect(wrong == .unreachable(.authenticationHTTPS))
        let missing = await RemoteProbe.run(url: "-oops", credentials: nil)
        #expect(missing == .unreachable(nil))
    }
}
