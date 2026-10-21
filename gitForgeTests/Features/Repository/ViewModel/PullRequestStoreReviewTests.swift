import Foundation
import Testing
@testable import gitForge

/// Two open PRs by someone else, a fixed detail per number, and how often
/// each detail was fetched.
private final class ReviewFakeProvider: PullRequestProvider, @unchecked Sendable {
    private(set) var detailFetches: [Int: Int] = [:]

    static func pull(_ number: Int) -> PullRequest {
        PullRequest(id: "\(number)", number: number, title: "PR \(number)", state: .open, authorLogin: "marta",
                    authorAvatarURL: nil, sourceBranch: "feature/\(number)", targetBranch: "main", webURL: nil,
                    createdAt: nil, updatedAt: nil, headSha: "sha\(number)")
    }

    func fetchPulls(host: RemoteHost, state: PullListState, token: String) async throws -> [PullRequest] {
        state == .open ? [Self.pull(1), Self.pull(2)] : []
    }
    func fetchCurrentUser(host: RemoteHost, token: String) async throws -> String { "user-of-\(token)" }
    func fetchChecks(host: RemoteHost, pull: PullRequest, token: String) async throws -> [CICheck] { [] }
    func fetchCommitChecks(host: RemoteHost, sha: String, token: String) async throws -> [CICheck] { [] }
    func fetchDetail(host: RemoteHost, number: Int, token: String) async throws -> PullRequestDetail {
        detailFetches[number, default: 0] += 1
        return PullRequestDetail(pull: Self.pull(number), descriptionMarkdown: nil, labels: [], reviewers: [], assignees: [],
                                 mergeable: true, ciStatus: nil)
    }
    func fetchCommits(host: RemoteHost, number: Int, token: String) async throws -> [PullRequestCommit] { [] }
    func fetchFiles(host: RemoteHost, number: Int, token: String) async throws -> [PullRequestFileChange] { [] }
}

/// Records each review, throws what the test queues, and can hold a review
/// until the test opens `gate`.
private final class FakeReviewProvider: PullRequestReviewProvider, @unchecked Sendable {
    struct Call: Equatable {
        let number: Int
        let verdict: ReviewVerdict
        let body: String
        let token: String
    }
    private(set) var calls: [Call] = []
    private(set) var landed: [Call] = []
    var errors: [Error] = []
    var warning: String?
    var gate: AsyncGate?

    func requestChangesSupport(host: RemoteHost, token: String) async -> RequestChangesSupport { .supported }

    func submitReview(host: RemoteHost, pull: PullRequest, verdict: ReviewVerdict, body: String, token: String) async throws -> String? {
        let call = Call(number: pull.number, verdict: verdict, body: body, token: token)
        calls.append(call)
        if let gate { await gate.wait() }
        if !errors.isEmpty { throw errors.removeFirst() }
        landed.append(call)
        return warning
    }

    func fetchMergeOptions(host: RemoteHost, pull: PullRequest, detail: PullRequestDetail,
                           commits: [PullRequestCommit], token: String) async throws -> MergeOptions {
        MergeOptions(kind: .github(methods: [.squash]), canDeleteSourceBranch: true, initialMethod: .squash, initialSquash: false)
    }

    func merge(host: RemoteHost, pull: PullRequest, input: MergeInput, token: String) async throws -> MergeOutcome {
        MergeOutcome(branchDeleted: input.deleteSourceBranch)
    }

    func fetchThreads(host: RemoteHost, pull: PullRequest, detail: PullRequestDetail?, token: String) async throws -> [ReviewThread] {
        []
    }
    func addComment(host: RemoteHost, pull: PullRequest, detail: PullRequestDetail?, target: CommentTarget,
                    body: String, token: String) async throws {}
    func reply(host: RemoteHost, pull: PullRequest, thread: ReviewThread, body: String, token: String) async throws {}
    func setResolved(_ resolved: Bool, host: RemoteHost, pull: PullRequest, thread: ReviewThread, token: String) async throws {}
}

/// The tokens `auth` was told were rejected.
@MainActor
private final class AuthLog {
    var rejected: [String] = []
}

@Suite("PullRequestStore — reviews", .serialized)
@MainActor
struct PullRequestStoreReviewTests {
    nonisolated static let host = RemoteHost(provider: .github, host: "github.com", owner: "octo", repo: "app")

    private let provider = ReviewFakeProvider()
    private let reviews = FakeReviewProvider()
    private let auth = AuthLog()

    /// A loaded list with PR 1's detail open (loaded directly, so the fetch
    /// count is deterministic).
    private func loadedStore() async -> PullRequestStore {
        let provider = provider
        let reviews = reviews
        let auth = auth
        let store = PullRequestStore(cli: GitCLI(workingDirectory: URL(fileURLWithPath: "/var/empty")),
                                     auth: { _, rejected in
                                         if let rejected { auth.rejected.append(rejected) }
                                         return rejected == nil ? .token("t1") : .token("t2")
                                     },
                                     resolveHost: { Self.host },
                                     makeProvider: { _ in provider },
                                     makeReviewProvider: { _ in reviews })
        await store.load(force: true)
        store.selected = store.items.first
        await store.loadDetail()
        return store
    }

    @Test("Request changes with only spaces isn't sent")
    func blankRequestChanges() async {
        let store = await loadedStore()
        store.drafts[.review(pullId: "1", .requestChanges)] = "  \n"
        #expect(await store.submitReview(.requestChanges) == .ignored)
        #expect(reviews.calls.isEmpty)
    }

    @Test("Approve sends the draft, clears it and reloads the detail")
    func approve() async {
        let store = await loadedStore()
        store.drafts[.review(pullId: "1", .approve)] = "LGTM"
        #expect(await store.submitReview(.approve) == .submitted(warning: nil))
        #expect(reviews.landed == [.init(number: 1, verdict: .approve, body: "LGTM", token: "t1")])
        #expect(store.drafts[.review(pullId: "1", .approve)] == nil)
        #expect(provider.detailFetches[1] == 2)
        #expect(store.submittingReview == nil)
    }

    @Test("A 401 gets one fresh token and one retry")
    func retriesAfter401() async {
        let store = await loadedStore()
        reviews.errors = [PullRequestFetchError.unauthorized]
        #expect(await store.submitReview(.approve) == .submitted(warning: nil))
        #expect(reviews.calls.map(\.token) == ["t1", "t2"])
        #expect(reviews.landed.count == 1)
    }

    @Test("A 403 says which account can't, and keeps the draft")
    func forbidden() async {
        let store = await loadedStore()
        store.drafts[.review(pullId: "1", .approve)] = "LGTM"
        reviews.errors = [PullRequestFetchError.forbidden]
        #expect(await store.submitReview(.approve)
                == .failed("Your account (user-of-t1 on github.com) can't approve this pull request."))
        #expect(store.drafts[.review(pullId: "1", .approve)] == "LGTM")
        #expect(store.submittingReview == nil)
    }

    @Test("GitLab: approval kept when the comment fails")
    func warning() async {
        let store = await loadedStore()
        reviews.warning = "Approved, but the comment couldn't be posted: boom"
        #expect(await store.submitReview(.approve) == .submitted(warning: "Approved, but the comment couldn't be posted: boom"))
    }

    @Test("Switching PR mid-submit: the review goes to the first PR and the second isn't reloaded by it")
    func switchMidSubmit() async throws {
        let store = await loadedStore()
        let gate = AsyncGate()
        reviews.gate = gate
        let submit = Task { await store.submitReview(.approve) }
        await gate.waiting()
        let second = try #require(store.items.last)
        store.select(second)
        await waitUntil { store.detail?.pull.number == 2 && !store.isLoadingDetail }
        gate.open()
        #expect(await submit.value == .submitted(warning: nil))
        #expect(reviews.landed.map(\.number) == [1])
        #expect(provider.detailFetches[2] == 1)
        #expect(provider.detailFetches[1] == 1)
        #expect(store.detail?.pull.number == 2)
    }

    @Test("A refused review never asks for a fresh token, and reloads the detail")
    func refused() async {
        let store = await loadedStore()
        reviews.errors = [PullRequestActionError.rejected("the approval wasn't accepted")]
        #expect(await store.submitReview(.approve) == .failed("The host refused: the approval wasn't accepted"))
        #expect(auth.rejected.isEmpty)
        #expect(provider.detailFetches[1] == 2)
    }

    @Test("New commits on the host: says so, reloads the detail and keeps the draft")
    func headChanged() async {
        let store = await loadedStore()
        store.drafts[.review(pullId: "1", .requestChanges)] = "Add tests"
        reviews.errors = [PullRequestFetchError.server(409, "{}")]
        #expect(await store.submitReview(.requestChanges) == .failed("New commits were pushed — review them and try again."))
        #expect(provider.detailFetches[1] == 2)
        #expect(store.drafts[.review(pullId: "1", .requestChanges)] == "Add tests")
    }

    @Test("A verdict that landed without its comment keeps the comment's draft")
    func warningKeepsDraft() async {
        let store = await loadedStore()
        store.drafts[.review(pullId: "1", .approve)] = "LGTM"
        reviews.warning = "Approved, but the comment couldn't be posted: boom"
        #expect(await store.submitReview(.approve) == .submitted(warning: "Approved, but the comment couldn't be posted: boom"))
        #expect(store.drafts[.review(pullId: "1", .approve)] == "LGTM")
    }

    @Test("Request changes support is read with the detail")
    func support() async {
        let store = await loadedStore()
        #expect(store.requestChangesSupport == .supported)
        #expect(store.reviewActions == ReviewActions(approve: .available, requestChanges: .available))
    }
}
