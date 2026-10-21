import Foundation
import Testing
@testable import gitForge

/// Three open PRs by someone else. Reads and merges in one double: the
/// detail's merge status comes from `statuses` (served in order, the last
/// one repeats), and a merged PR leaves the open list.
private final class MergeFakeProvider: PullRequestProvider, PullRequestReviewProvider, @unchecked Sendable {
    var statuses: [HostMergeStatus?] = [HostMergeStatus(verdict: .ready)]
    var headInSameRepo: Bool? = true
    var viewerCanMerge: Bool?
    /// Left out of the open list, as if closed elsewhere.
    var hidden: Set<Int> = []
    var mergeErrors: [Error] = []
    var optionsError: Error?
    /// `nil`: the branch goes when asked.
    var outcome: MergeOutcome?
    private(set) var merged: Set<Int> = []
    private(set) var detailFetches: [Int: Int] = [:]
    private(set) var merges: [(number: Int, input: MergeInput, token: String)] = []
    private(set) var optionFetches = 0

    static func pull(_ number: Int, state: PullRequest.State = .open) -> PullRequest {
        PullRequest(id: "\(number)", number: number, title: "PR \(number)", state: state, authorLogin: "marta",
                    authorAvatarURL: nil, sourceBranch: "feature/\(number)", targetBranch: "main", webURL: nil,
                    createdAt: nil, updatedAt: nil, headSha: "sha\(number)")
    }

    func fetchPulls(host: RemoteHost, state: PullListState, token: String) async throws -> [PullRequest] {
        guard state == .open else { return merged.sorted().map { Self.pull($0, state: .merged) } }
        return [1, 2, 3].filter { !merged.contains($0) && !hidden.contains($0) }.map { Self.pull($0) }
    }
    func fetchCurrentUser(host: RemoteHost, token: String) async throws -> String { "user-of-\(token)" }
    func fetchChecks(host: RemoteHost, pull: PullRequest, token: String) async throws -> [CICheck] { [] }
    func fetchCommitChecks(host: RemoteHost, sha: String, token: String) async throws -> [CICheck] { [] }
    func fetchDetail(host: RemoteHost, number: Int, token: String) async throws -> PullRequestDetail {
        detailFetches[number, default: 0] += 1
        let status = statuses.count > 1 ? statuses.removeFirst() : statuses.first ?? nil
        let isMerged = merged.contains(number)
        return PullRequestDetail(pull: Self.pull(number, state: isMerged ? .merged : .open), descriptionMarkdown: nil,
                                 labels: [], reviewers: [], assignees: [], mergeable: true, ciStatus: nil,
                                 hostMergeStatus: isMerged ? nil : status, headInSameRepo: headInSameRepo,
                                 viewerCanMerge: viewerCanMerge)
    }
    func fetchCommits(host: RemoteHost, number: Int, token: String) async throws -> [PullRequestCommit] { [] }
    func fetchFiles(host: RemoteHost, number: Int, token: String) async throws -> [PullRequestFileChange] { [] }

    func requestChangesSupport(host: RemoteHost, token: String) async -> RequestChangesSupport { .supported }
    func submitReview(host: RemoteHost, pull: PullRequest, verdict: ReviewVerdict, body: String, token: String) async throws -> String? { nil }

    func fetchMergeOptions(host: RemoteHost, pull: PullRequest, detail: PullRequestDetail,
                           commits: [PullRequestCommit], token: String) async throws -> MergeOptions {
        optionFetches += 1
        if let optionsError { throw optionsError }
        return MergeOptions(kind: .github(methods: [.squash, .merge]), canDeleteSourceBranch: detail.headInSameRepo == true,
                            initialMethod: .squash, initialSquash: false)
    }

    func merge(host: RemoteHost, pull: PullRequest, input: MergeInput, token: String) async throws -> MergeOutcome {
        merges.append((pull.number, input, token))
        if !mergeErrors.isEmpty { throw mergeErrors.removeFirst() }
        merged.insert(pull.number)
        return outcome ?? MergeOutcome(branchDeleted: input.deleteSourceBranch)
    }
}

@Suite("PullRequestStore — merge", .serialized)
@MainActor
struct PullRequestStoreMergeTests {
    nonisolated static let host = RemoteHost(provider: .github, host: "github.com", owner: "octo", repo: "app")

    private let provider = MergeFakeProvider()

    init() {
        PullRequestStore.mergeStatusRecheckDelay = .zero
    }

    /// A loaded list with PR 1's detail open (loaded directly, so the fetch
    /// count is deterministic), any recheck awaited.
    private func loadedStore() async -> PullRequestStore {
        let provider = provider
        let store = PullRequestStore(cli: GitCLI(workingDirectory: URL(fileURLWithPath: "/var/empty")),
                                     auth: { _, rejected in rejected == nil ? .token("t1") : .token("t2") },
                                     resolveHost: { Self.host },
                                     makeProvider: { _ in provider },
                                     makeReviewProvider: { _ in provider })
        await store.load(force: true)
        store.selected = store.items.first
        await store.loadDetail()
        await store.mergeStatusRecheck?.value
        return store
    }

    /// A store ready to merge PR 1: detail loaded, sheet prepared.
    private func preparedStore() async -> PullRequestStore {
        let store = await loadedStore()
        await store.prepareMerge()
        return store
    }

    // MARK: Status

    @Test("Unknown merge status rechecks once")
    func recheck() async {
        provider.statuses = [HostMergeStatus(verdict: .waiting, reasons: ["checking mergeability…"], stillComputing: true),
                             HostMergeStatus(verdict: .ready)]
        let store = await loadedStore()
        #expect(provider.detailFetches[1] == 2)
        #expect(store.mergeReadiness?.kind == .ready)
        #expect(store.mergeReadiness?.canMerge == true)
    }

    @Test("Still unknown after the recheck: the recheck doesn't chain, and nothing merges")
    func recheckDoesntChain() async {
        provider.statuses = [HostMergeStatus(verdict: .waiting, reasons: ["checking mergeability…"], stillComputing: true)]
        let store = await loadedStore()
        #expect(provider.detailFetches[1] == 2)
        #expect(store.mergeReadiness?.kind == .waiting)
        #expect(store.mergeReadiness?.canMerge == false)
    }

    @Test("A later load gets its own recheck: after a 409 the status isn't left computing")
    func recheckAfterHeadChanged() async {
        let computing = HostMergeStatus(verdict: .waiting, reasons: ["checking mergeability…"], stillComputing: true)
        provider.statuses = [computing, HostMergeStatus(verdict: .ready), computing, HostMergeStatus(verdict: .ready)]
        let store = await preparedStore()
        provider.mergeErrors = [PullRequestFetchError.server(409, "{}")]
        _ = await store.merge()
        await store.mergeStatusRecheck?.value
        #expect(provider.detailFetches[1] == 4)
        #expect(store.mergeReadiness?.canMerge == true)
    }

    @Test("Selecting another PR rechecks it again")
    func recheckPerSelection() async {
        provider.statuses = [HostMergeStatus(verdict: .waiting, reasons: ["checking mergeability…"], stillComputing: true)]
        let store = await loadedStore()
        store.select(store.items[1])
        await waitUntil { provider.detailFetches[2] == 2 && !store.isLoadingDetail }
        #expect(provider.detailFetches[2] == 2)
    }

    // MARK: Options

    @Test("Preparing reads the options and starts a fresh draft")
    func prepare() async {
        let store = await preparedStore()
        #expect(store.mergeOptions?.kind == .github(methods: [.squash, .merge]))
        #expect(store.mergeDraft == MergeDraft(options: store.mergeOptions!))
        #expect(store.mergeOptionsError == nil)
        #expect(!store.isLoadingMergeOptions)
    }

    @Test("Options that can't load say why")
    func prepareFails() async {
        provider.optionsError = PullRequestFetchError.server(500, "boom")
        let store = await preparedStore()
        #expect(store.mergeOptions == nil && store.mergeDraft == nil)
        #expect(store.mergeOptionsError == "Server returned 500: boom")
    }

    // MARK: Merge

    @Test("Blocked by the host: merge isn't sent")
    func blocked() async {
        provider.statuses = [HostMergeStatus(verdict: .blocked, reasons: ["all threads must be resolved"])]
        let store = await preparedStore()
        #expect(await store.merge() == .failed("All threads must be resolved."))
        #expect(provider.merges.isEmpty)
    }

    @Test("An account the host says can't merge: Merge… is off and nothing is sent")
    func accountCantMerge() async {
        provider.viewerCanMerge = false
        let store = await preparedStore()
        #expect(store.mergeReadiness?.canMerge == false)
        #expect(await store.merge() == .failed("Your account can't merge it."))
        #expect(provider.merges.isEmpty)
    }

    @Test("Merge sends the draft pinned to the head, then reloads the list and the detail")
    func merge() async {
        let store = await preparedStore()
        let fetches = provider.detailFetches[1] ?? 0
        #expect(await store.merge() == .merged(warning: nil))
        #expect(provider.merges.map(\.number) == [1])
        #expect(provider.merges.first?.input == MergeInput(method: .squash, squash: true, deleteSourceBranch: true,
                                                           messages: [:], headSha: "sha1"))
        #expect(provider.detailFetches[1] == fetches + 1)
        #expect(store.items.map(\.number) == [2, 3])
        #expect(store.mergeDraft == nil)
        #expect(!store.isMerging)
    }

    @Test("A 401 gets one fresh token and one retry, merging once")
    func retriesAfter401() async {
        let store = await preparedStore()
        provider.mergeErrors = [PullRequestFetchError.unauthorized]
        #expect(await store.merge() == .merged(warning: nil))
        #expect(provider.merges.map(\.token) == ["t1", "t2"])
        #expect(provider.merged == [1])
    }

    @Test("Head changed: says so, reloads the detail, isn't marked merged")
    func headChanged() async {
        let store = await preparedStore()
        provider.mergeErrors = [PullRequestFetchError.server(409, "{}")]
        let fetches = provider.detailFetches[1] ?? 0
        #expect(await store.merge() == .headChanged("New commits were pushed — review them before merging."))
        #expect(provider.detailFetches[1] == fetches + 1)
        #expect(store.selected?.state == .open)
        #expect(store.items.map(\.number) == [1, 2, 3])
    }

    @Test("No merge rights: says which account")
    func forbidden() async {
        let store = await preparedStore()
        provider.mergeErrors = [PullRequestFetchError.forbidden]
        #expect(await store.merge() == .failed("Your account (user-of-t1 on github.com) can't merge this pull request."))
        #expect(store.mergeDraft != nil)
    }

    @Test("Branch kept: merged with a warning naming it")
    func branchKept() async {
        provider.outcome = MergeOutcome(branchDeleted: false)
        let store = await preparedStore()
        #expect(await store.merge() == .merged(warning: "Merged #1, but feature/1 couldn't be deleted."))
    }

    @Test("Branch kept on purpose: no warning")
    func branchKeptOnPurpose() async {
        let store = await preparedStore()
        store.mergeDraft?.deleteSourceBranch = false
        #expect(await store.merge() == .merged(warning: nil))
        #expect(provider.merges.first?.input.deleteSourceBranch == false)
    }

    @Test("Fork: the draft never asks to delete")
    func fork() async {
        provider.headInSameRepo = false
        let store = await preparedStore()
        store.mergeDraft?.deleteSourceBranch = true
        #expect(await store.merge() == .merged(warning: nil))
        #expect(provider.merges.first?.input.deleteSourceBranch == false)
    }

    @Test("Nothing prepared: nothing sent")
    func notPrepared() async {
        let store = await loadedStore()
        #expect(await store.merge() == .ignored)
        #expect(provider.merges.isEmpty)
    }

    // MARK: Selection

    @Test("The merged PR stays selected outside the list until another is picked")
    func keepsSelection() async {
        let store = await preparedStore()
        _ = await store.merge()
        #expect(!store.items.contains { $0.id == "1" })
        #expect(store.selected?.id == "1")
        #expect(store.selected?.state == .merged)
        #expect(store.pullToAutoSelect() == nil)

        let other = store.items[0]
        store.select(other)
        provider.hidden = [other.number]
        await store.load(force: true)
        #expect(store.pullToAutoSelect()?.id == "3")
    }

    @Test("Auto-select: the first row when nothing or a missing row is selected")
    func autoSelect() async {
        let store = await loadedStore()
        #expect(store.pullToAutoSelect() == nil)
        store.closeDetail()
        #expect(store.pullToAutoSelect()?.id == "1")
        store.selected = MergeFakeProvider.pull(9)
        #expect(store.pullToAutoSelect()?.id == "1")
    }

    @Test("Selecting a PR drops the previous merge sheet's state")
    func selectClears() async {
        let store = await preparedStore()
        store.select(store.items[1])
        #expect(store.mergeOptions == nil && store.mergeDraft == nil && store.mergeOptionsError == nil)
    }
}
