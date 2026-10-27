import Foundation
import Testing
@testable import gitForge

/// Two open PRs by `author`; the detail's merge status, reviewers and
/// failure are set per test, and its read can wait on a gate.
private final class QuickFakeProvider: PullRequestProvider, PullRequestReviewProvider, @unchecked Sendable {
    var status: HostMergeStatus? = HostMergeStatus(verdict: .ready)
    var reviewers: [PullRequestDetail.Reviewer] = []
    var author = "marta"
    var detailGate: AsyncGate?
    var failDetail = false
    private(set) var detailFetches = 0

    func pull(_ number: Int) -> PullRequest {
        PullRequest(id: "\(number)", number: number, title: "PR \(number)", state: .open, authorLogin: author,
                    authorAvatarURL: nil, sourceBranch: "feature/\(number)", targetBranch: "main", webURL: nil,
                    createdAt: nil, updatedAt: nil, listStatus: PullListStatus(kind: .ready))
    }

    func fetchPulls(host: RemoteHost, state: PullListState, token: String) async throws -> [PullRequest] {
        state == .open ? [pull(1), pull(2)] : []
    }
    func fetchCurrentUser(host: RemoteHost, token: String) async throws -> String { "octo" }
    func fetchChecks(host: RemoteHost, pull: PullRequest, token: String) async throws -> [CICheck] { [] }
    func fetchCommitChecks(host: RemoteHost, sha: String, token: String) async throws -> [CICheck] { [] }
    func fetchDetail(host: RemoteHost, number: Int, token: String) async throws -> PullRequestDetail {
        detailFetches += 1
        if let detailGate { await detailGate.wait() }
        if failDetail { throw PullRequestFetchError.server(500, "boom") }
        return PullRequestDetail(pull: pull(number), descriptionMarkdown: nil, labels: [], reviewers: reviewers,
                                 assignees: [], mergeable: true, ciStatus: nil, hostMergeStatus: status,
                                 headInSameRepo: true, viewerCanMerge: true)
    }
    func fetchCommits(host: RemoteHost, number: Int, token: String) async throws -> [PullRequestCommit] { [] }
    func fetchFiles(host: RemoteHost, number: Int, token: String) async throws -> [PullRequestFileChange] { [] }

    func requestChangesSupport(host: RemoteHost, token: String) async -> RequestChangesSupport { .supported }
    func submitReview(host: RemoteHost, pull: PullRequest, verdict: ReviewVerdict, body: String,
                      token: String) async throws -> String? { nil }
    func fetchMergeOptions(host: RemoteHost, pull: PullRequest, detail: PullRequestDetail,
                           commits: [PullRequestCommit], token: String) async throws -> MergeOptions {
        throw PullRequestFetchError.notFound
    }
    func merge(host: RemoteHost, pull: PullRequest, input: MergeInput, token: String) async throws -> MergeOutcome {
        throw PullRequestFetchError.notFound
    }
    func fetchThreads(host: RemoteHost, pull: PullRequest, detail: PullRequestDetail?,
                      token: String) async throws -> [ReviewThread] { [] }
    func addComment(host: RemoteHost, pull: PullRequest, detail: PullRequestDetail?, target: CommentTarget,
                    body: String, token: String) async throws {}
    func reply(host: RemoteHost, pull: PullRequest, thread: ReviewThread, body: String, token: String) async throws {}
    func setResolved(_ resolved: Bool, host: RemoteHost, pull: PullRequest, thread: ReviewThread,
                     token: String) async throws {}
}

@Suite("PullRequestStore — a row's quick actions", .serialized)
@MainActor
struct PullRequestStoreQuickActionTests {
    nonisolated static let host = RemoteHost(provider: .github, host: "github.com", owner: "octo", repo: "app")

    private let provider = QuickFakeProvider()

    private func loadedStore() async -> PullRequestStore {
        let provider = provider
        let store = PullRequestStore(cli: GitCLI(workingDirectory: URL(fileURLWithPath: "/var/empty")),
                                     auth: { _, _ in .token("t1") },
                                     resolveHost: { Self.host },
                                     makeProvider: { _ in provider },
                                     makeReviewProvider: { _ in provider })
        store.mergeStatusRecheckDelay = .zero
        await store.load(force: true)
        return store
    }

    private func settled(_ store: PullRequestStore) async {
        await waitUntil { !store.isLoadingDetail && (store.detail != nil || store.detailError != nil) }
    }

    @Test("Merge on a row selects it and, once its detail allows it, opens the sheet")
    func mergeWhenReady() async {
        let store = await loadedStore()
        store.requestQuickAction(.merge, on: store.items[1])
        #expect(store.selected?.number == 2)
        #expect(store.pendingQuickAction == PendingPullQuickAction(pullNumber: 2, action: .merge))
        await settled(store)
        #expect(store.takeQuickAction() == .perform(.merge))
        #expect(store.pendingQuickAction == nil)
        #expect(store.takeQuickAction() == nil)
    }

    @Test("While the detail loads the quick action waits, and stays")
    func waitsWhileLoading() async {
        let gate = AsyncGate()
        provider.detailGate = gate
        let store = await loadedStore()
        store.requestQuickAction(.approve, on: store.items[0])
        await gate.waiting()
        #expect(store.takeQuickAction() == nil)
        #expect(store.pendingQuickAction != nil)
        gate.open()
        await settled(store)
        #expect(store.takeQuickAction() == .perform(.approve))
    }

    @Test("Merge the detail blocks: refused with the banner's reason")
    func mergeBlocked() async {
        provider.status = HostMergeStatus(verdict: .blocked, reasons: ["needs approval"])
        let store = await loadedStore()
        store.requestQuickAction(.merge, on: store.items[0])
        await settled(store)
        guard case .refused(let reason) = store.takeQuickAction() else {
            Issue.record("Expected a refusal")
            return
        }
        #expect(reason.contains("Needs approval."))
        #expect(store.pendingQuickAction == nil)
    }

    @Test("Approve on one the user already approved, or on the user's own: refused")
    func approveRefused() async {
        provider.reviewers = [.init(login: "octo", state: .approved)]
        let approved = await loadedStore()
        approved.requestQuickAction(.approve, on: approved.items[0])
        await settled(approved)
        #expect(approved.takeQuickAction() == .refused(String(localized: "You've already approved it.")))

        provider.reviewers = []
        provider.author = "octo"
        let own = await loadedStore()
        own.requestQuickAction(.approve, on: own.items[0])
        await settled(own)
        #expect(own.takeQuickAction() == .refused(String(localized: "You can't approve it.")))
    }

    @Test("Another row selected meanwhile: the quick action goes, with nothing to say")
    func selectionMoved() async {
        let store = await loadedStore()
        store.requestQuickAction(.merge, on: store.items[0])
        store.select(store.items[1])
        await settled(store)
        #expect(store.takeQuickAction() == nil)
        #expect(store.pendingQuickAction == nil)
    }

    @Test("A detail that can't load drops the quick action: the detail says why")
    func detailFailed() async {
        provider.failDetail = true
        let store = await loadedStore()
        store.requestQuickAction(.merge, on: store.items[0])
        await settled(store)
        #expect(store.detailError != nil)
        #expect(store.takeQuickAction() == nil)
        #expect(store.pendingQuickAction == nil)
    }

    @Test("On the row already open, nothing is read again")
    func sameRowNoReload() async {
        let store = await loadedStore()
        store.select(store.items[0])
        await settled(store)
        let fetches = provider.detailFetches
        store.requestQuickAction(.merge, on: store.items[0])
        #expect(store.takeQuickAction() == .perform(.merge))
        #expect(provider.detailFetches == fetches)
    }
}
