import Foundation
import Testing
@testable import gitForge

/// Answers with a fixed list; the first `rejectFirst` calls throw unauthorized.
private final class AuthFakeProvider: PullRequestProvider, @unchecked Sendable {
    var rejectFirst = 0
    var failWith: PullRequestFetchError?
    var closedRejections = 0
    var detailRejections = 0
    private(set) var tokens: [String] = []
    private(set) var closedTokens: [String] = []
    private(set) var detailTokens: [String] = []
    func fetchPulls(host: RemoteHost, state: PullListState, token: String) async throws -> [PullRequest] {
        if state == .closed {
            closedTokens.append(token)
            if closedRejections > 0 { closedRejections -= 1; throw PullRequestFetchError.unauthorized }
            return []
        }
        tokens.append(token)
        if let failWith { throw failWith }
        if rejectFirst > 0 { rejectFirst -= 1; throw PullRequestFetchError.unauthorized }
        return [PullRequest(id: "1", number: 1, title: "PR", state: .open, authorLogin: "octo", authorAvatarURL: nil,
                            sourceBranch: "f", targetBranch: "main", webURL: nil, createdAt: nil, updatedAt: nil)]
    }
    func fetchCurrentUser(host: RemoteHost, token: String) async throws -> String { "user-of-\(token)" }
    func fetchChecks(host: RemoteHost, pull: PullRequest, token: String) async throws -> [CICheck] { [] }
    func fetchDetail(host: RemoteHost, number: Int, token: String) async throws -> PullRequestDetail {
        detailTokens.append(token)
        if detailRejections > 0 { detailRejections -= 1; throw PullRequestFetchError.unauthorized }
        return PullRequestDetail(pull: PullRequest(id: "1", number: 1, title: "PR", state: .open, authorLogin: "octo",
                                                   authorAvatarURL: nil, sourceBranch: "f", targetBranch: "main",
                                                   webURL: nil, createdAt: nil, updatedAt: nil),
                                 descriptionMarkdown: nil, labels: [], reviewers: [], assignees: [], mergeable: true, ciStatus: nil)
    }
    func fetchCommits(host: RemoteHost, number: Int, token: String) async throws -> [PullRequestCommit] { [] }
    func fetchFiles(host: RemoteHost, number: Int, token: String) async throws -> [PullRequestFileChange] { [] }
}

/// A value the test changes between loads.
@MainActor
private final class Answer<T> {
    var value: T
    init(_ value: T) { self.value = value }
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

    @Test("An undeclared GitHub/GitLab-looking origin offers to add it as an instance")
    func suggestsInstance() async {
        let suggestion = InstanceSuggestion(host: "gitlab.example.org", kind: .gitlab)
        let s = PullRequestStore(cli: GitCLI(workingDirectory: URL(fileURLWithPath: "/var/empty")),
                                 auth: { _, _ in .token("test-token") },
                                 resolveHost: { nil },
                                 suggestInstance: { suggestion },
                                 makeProvider: { _ in AuthFakeProvider() })
        await s.load(force: true)
        #expect(s.host == nil)
        #expect(s.suggestedInstance == suggestion)
        #expect(!s.requiresToken)
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

    @Test("A token that goes bad after the list loads: Closed and the detail get one fresh token and retry")
    func laterRetries() async {
        let provider = AuthFakeProvider()
        let s = store(provider) { _, rejected in rejected == nil ? .token("test-old") : .token("test-new") }
        await s.load(force: true)
        provider.closedRejections = 1
        await s.setScope(.closed)
        #expect(provider.closedTokens == ["test-old", "test-new"])
        #expect(s.error == nil)
        provider.detailRejections = 1
        s.selected = s.items.first
        await s.loadDetail()
        #expect(provider.detailTokens == ["test-new", "test-new"] || provider.detailTokens.last == "test-new")
        #expect(s.detail != nil)
        #expect(s.detailError == nil)
    }

    @Test("A failure getting the token (offline) shows as an error, not as Connect")
    func authFailure() async {
        let s = store(AuthFakeProvider()) { _, _ in .failed("Couldn't reach the server: offline") }
        await s.load(force: true)
        #expect(!s.requiresToken)
        #expect(s.error == "Couldn't reach the server: offline")
    }

    @Test("Cancelling the account sheet: no account chosen, not an empty list; choosing later loads")
    func cancelled() async {
        let answer = Answer(PullRequestAuthResult.cancelled)
        let s = store(AuthFakeProvider()) { _, _ in answer.value }
        await s.load(force: true)
        #expect(!s.isLoading)
        #expect(!s.requiresToken)
        #expect(s.accountNotChosen)
        #expect(s.error == nil)
        #expect(s.items.isEmpty)

        answer.value = .token("test-token")
        await s.load(force: true)
        #expect(!s.accountNotChosen)
        #expect(s.items.count == 1)
    }

    @Test("Another token (reconnected, or another account): Mine follows the new login")
    func currentUserFollowsToken() async {
        let token = Answer("token-a")
        let s = store(AuthFakeProvider()) { _, _ in .token(token.value) }
        await s.load(force: true)
        #expect(s.currentUser == "user-of-token-a")
        token.value = "token-b"
        await s.load(force: true)
        #expect(s.currentUser == "user-of-token-b")
    }
}
