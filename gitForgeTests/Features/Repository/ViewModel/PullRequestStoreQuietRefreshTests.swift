import Foundation
import Testing
@testable import gitForge

/// Scripted provider for the quiet refresh: open and closed lists, tokens it
/// rejects, and how many times each list was read.
private final class QuietFakeProvider: PullRequestProvider, @unchecked Sendable {
    var open: [PullRequest] = []
    var closed: [PullRequest] = []
    /// Tokens answered with a 401.
    var rejecting: Set<String> = []
    /// What reading the open list throws, while set (after the token check).
    var openFailure: PullRequestFetchError?
    private(set) var openFetches = 0
    private(set) var closedFetches = 0
    private(set) var openTokens: [String] = []

    func fetchPulls(host: RemoteHost, state: PullListState, token: String) async throws -> [PullRequest] {
        if state == .closed {
            closedFetches += 1
            return closed
        }
        openFetches += 1
        openTokens.append(token)
        if rejecting.contains(token) { throw PullRequestFetchError.unauthorized }
        if let openFailure { throw openFailure }
        return open
    }
    func fetchCurrentUser(host: RemoteHost, token: String) async throws -> String { "marta" }
    func fetchChecks(host: RemoteHost, pull: PullRequest, token: String) async throws -> [CICheck] { [] }
    func fetchCommitChecks(host: RemoteHost, sha: String, token: String) async throws -> [CICheck] { [] }
    func fetchDetail(host: RemoteHost, number: Int, token: String) async throws -> PullRequestDetail {
        throw PullRequestFetchError.notFound
    }
    func fetchCommits(host: RemoteHost, number: Int, token: String) async throws -> [PullRequestCommit] { [] }
    func fetchFiles(host: RemoteHost, number: Int, token: String) async throws -> [PullRequestFileChange] { [] }
}

/// The background re-read of the open list that the inbox's auto refresh
/// runs for the open repository (U1 final review residual): never asks for
/// an account, never shows a spinner, an error or a connect state, and
/// leaves Closed alone.
@Suite("PullRequestStore — quiet refresh", .serialized)
@MainActor
struct PullRequestStoreQuietRefreshTests {

    /// What the store's two auth closures were asked, and what they answer.
    private final class AuthLog {
        var interactive = 0
        var silent: [String?] = []
        var interactiveAnswer: PullRequestAuthResult = .token("t1")
        var silentAnswer: PullRequestAuthResult = .token("t2")
    }

    private static func pr(_ number: Int, by author: String, state: PullRequest.State = .open) -> PullRequest {
        PullRequest(id: "\(number)", number: number, title: "PR \(number)", state: state, authorLogin: author,
                    authorAvatarURL: nil, sourceBranch: "f/\(number)", targetBranch: "main", webURL: nil,
                    createdAt: nil, updatedAt: nil)
    }

    private static func makeStore(_ provider: QuietFakeProvider, _ log: AuthLog) -> PullRequestStore {
        let host = RemoteHost(provider: .github, host: "github.com", owner: "oss", repo: "lib")
        return PullRequestStore(
            cli: nil,
            auth: { _, _ in
                log.interactive += 1
                return log.interactiveAnswer
            },
            silentAuth: { _, rejected in
                log.silent.append(rejected)
                return log.silentAnswer
            },
            resolveHost: { host },
            makeProvider: { _ in provider }
        )
    }

    @Test("Reads the open list again with the last token and leaves Closed as it was")
    func keepsClosed() async {
        let provider = QuietFakeProvider()
        provider.open = [Self.pr(1, by: "lucia")]
        provider.closed = [Self.pr(9, by: "lucia", state: .merged)]
        let log = AuthLog()
        let store = Self.makeStore(provider, log)
        await store.load(force: true)
        await store.setScope(.closed)
        #expect(store.closedLoaded)
        #expect(provider.closedFetches == 1)
        let loadedAt = store.lastLoadedAt
        provider.open = [Self.pr(1, by: "lucia"), Self.pr(2, by: "marta")]

        await store.refreshOpenListQuietly()

        #expect(store.items.map(\.number) == [1, 2])
        #expect(store.closedLoaded)
        #expect(store.closedItems.map(\.number) == [9])
        #expect(provider.closedFetches == 1)
        #expect(provider.openTokens.last == "t1")
        #expect(store.lastLoadedAt != loadedAt)
        #expect(log.interactive == 1)
        #expect(log.silent.isEmpty)
        #expect(!store.isLoading)
    }

    @Test("A rejected token is renewed without asking; the retry uses the new one")
    func renewsSilently() async {
        let provider = QuietFakeProvider()
        provider.open = [Self.pr(1, by: "lucia")]
        let log = AuthLog()
        let store = Self.makeStore(provider, log)
        await store.load(force: true)
        provider.rejecting = ["t1"]
        provider.open = [Self.pr(3, by: "lucia")]

        await store.refreshOpenListQuietly()

        #expect(log.interactive == 1)
        #expect(log.silent == ["t1"])
        #expect(provider.openTokens.suffix(2) == ["t1", "t2"])
        #expect(store.items.map(\.number) == [3])

        // The renewed token is the one the next read starts with.
        provider.rejecting = []
        await store.refreshOpenListQuietly()
        #expect(provider.openTokens.last == "t2")
    }

    @Test("When the token can't be renewed without asking, nothing changes on screen",
          arguments: [PullRequestAuthResult.cancelled,
                      .connectAccount(instanceId: nil, replacing: nil),
                      .failed("offline")])
    func unrenewableLeavesAlone(answer: PullRequestAuthResult) async {
        let provider = QuietFakeProvider()
        provider.open = [Self.pr(1, by: "lucia")]
        let log = AuthLog()
        log.silentAnswer = answer
        let store = Self.makeStore(provider, log)
        await store.load(force: true)
        provider.rejecting = ["t1"]

        await store.refreshOpenListQuietly()

        #expect(log.interactive == 1)
        #expect(store.items.map(\.number) == [1])
        #expect(store.error == nil)
        #expect(!store.requiresToken)
        #expect(!store.accountNotChosen)
    }

    @Test("A failed read keeps the list and shows no error")
    func failureKeepsList() async {
        let provider = QuietFakeProvider()
        provider.open = [Self.pr(1, by: "lucia")]
        let log = AuthLog()
        let store = Self.makeStore(provider, log)
        await store.load(force: true)
        provider.openFailure = .notFound

        await store.refreshOpenListQuietly()

        #expect(store.items.map(\.number) == [1])
        #expect(store.error == nil)
    }

    @Test("Before any successful load, nothing is read and nobody is asked")
    func neverLoaded() async {
        let provider = QuietFakeProvider()
        let log = AuthLog()
        let store = Self.makeStore(provider, log)

        await store.refreshOpenListQuietly()

        #expect(provider.openFetches == 0)
        #expect(log.interactive == 0)
        #expect(log.silent.isEmpty)
    }

    @Test("After the account chooser was cancelled, nothing is read and the chooser isn't shown again")
    func chooserCancelled() async {
        let provider = QuietFakeProvider()
        let log = AuthLog()
        log.interactiveAnswer = .cancelled
        let store = Self.makeStore(provider, log)
        await store.load(force: true)
        #expect(store.accountNotChosen)
        #expect(log.interactive == 1)

        await store.refreshOpenListQuietly()

        #expect(log.interactive == 1)
        #expect(log.silent.isEmpty)
        #expect(provider.openFetches == 0)
        #expect(store.accountNotChosen)
    }
}
