import Foundation
import Testing
@testable import gitForge

/// Answers with a fixed list; the first `rejectFirst` calls throw unauthorized.
private final class AuthFakeProvider: PullRequestProvider, @unchecked Sendable {
    var rejectFirst = 0
    var failWith: PullRequestFetchError?
    private(set) var tokens: [String] = []
    func fetchPulls(host: RemoteHost, state: PullListState, token: String) async throws -> [PullRequest] {
        tokens.append(token)
        if let failWith { throw failWith }
        if rejectFirst > 0 { rejectFirst -= 1; throw PullRequestFetchError.unauthorized }
        return [PullRequest(id: "1", number: 1, title: "PR", state: .open, authorLogin: "octo", authorAvatarURL: nil,
                            sourceBranch: "f", targetBranch: "main", webURL: nil, createdAt: nil, updatedAt: nil)]
    }
    func fetchCurrentUser(host: RemoteHost, token: String) async throws -> String { "octo" }
    func fetchChecks(host: RemoteHost, pull: PullRequest, token: String) async throws -> [CICheck] { [] }
    func fetchDetail(host: RemoteHost, number: Int, token: String) async throws -> PullRequestDetail { throw PullRequestFetchError.notFound }
    func fetchCommits(host: RemoteHost, number: Int, token: String) async throws -> [PullRequestCommit] { [] }
    func fetchFiles(host: RemoteHost, number: Int, token: String) async throws -> [PullRequestFileChange] { [] }
}

@Suite("PullRequestStore — account auth", .serialized)
@MainActor
struct PullRequestStoreAuthTests {
    nonisolated static let host = RemoteHost(provider: .github, host: "github.com", owner: "octo", repo: "app")

    private func store(_ provider: AuthFakeProvider,
                       auth: @escaping @MainActor (RemoteHost, String?) async -> PullRequestAuthResult) -> PullRequestStore {
        PullRequestStore(cli: GitCLI(workingDirectory: URL(fileURLWithPath: "/var/empty")),
                         auth: auth, resolveHost: { Self.host }, makeProvider: { _ in provider })
    }

    @Test("No credential: the store asks to connect on that instance")
    func connect() async {
        let instanceId = UUID()
        let s = store(AuthFakeProvider()) { _, _ in .connectAccount(instanceId: instanceId, replacing: nil) }
        await s.load(force: true)
        #expect(s.requiresToken)
        #expect(s.connectInstanceId == instanceId)
        #expect(s.items.isEmpty)
        #expect(s.error == nil)
    }

    @Test("A 401 asks once for a fresh token and retries")
    func retriesAfter401() async {
        let provider = AuthFakeProvider()
        provider.rejectFirst = 1
        let s = store(provider) { _, rejected in rejected == nil ? .token("test-old") : .token("test-new") }
        await s.load(force: true)
        #expect(provider.tokens == ["test-old", "test-new"])
        #expect(s.items.count == 1)
        #expect(!s.requiresToken)
    }

    @Test("A rejected token that can't be refreshed offers Reconnect, not an error")
    func reconnect() async {
        let provider = AuthFakeProvider()
        provider.rejectFirst = 5
        let accountId = UUID()
        let s = store(provider) { _, rejected in
            rejected == nil ? .token("test-old") : .connectAccount(instanceId: nil, replacing: accountId)
        }
        await s.load(force: true)
        #expect(s.requiresToken)
        #expect(s.reconnectAccountId == accountId)
        #expect(s.error == nil)
    }

    @Test("No access to the repo (404): an error with its message, not Connect")
    func notFound() async {
        let provider = AuthFakeProvider()
        provider.failWith = .notFound
        let s = store(provider) { _, _ in .token("test-token") }
        await s.load(force: true)
        #expect(!s.requiresToken)
        #expect(s.error == PullRequestFetchError.notFound.errorDescription)
    }

    @Test("Cancelling the account sheet leaves an empty list, no spinner, no error")
    func cancelled() async {
        let s = store(AuthFakeProvider()) { _, _ in .cancelled }
        await s.load(force: true)
        #expect(!s.isLoading)
        #expect(!s.requiresToken)
        #expect(s.error == nil)
        #expect(s.items.isEmpty)
    }
}
