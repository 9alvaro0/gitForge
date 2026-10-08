import Foundation
import Testing
@testable import gitForge

@Suite("PullRequestStore — detail state", .serialized)
@MainActor
struct RepositoryViewModelPullDetailTests {

    private static func makeVM() -> RepositoryViewModel {
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        return RepositoryViewModel(repository: Repository(url: url))
    }

    private static func pr(_ number: Int) -> PullRequest {
        PullRequest(
            id: "\(number)",
            number: number,
            title: "PR #\(number)",
            state: .open,
            authorLogin: nil,
            authorAvatarURL: nil,
            sourceBranch: "feature/\(number)",
            targetBranch: "main",
            webURL: nil,
            createdAt: nil,
            updatedAt: nil
        )
    }

    @Test("select clears prior detail state and bumps the gen-token")
    func selectClearsAndBumps() {
        let vm = Self.makeVM()
        // Pre-seed detail state from a previous PR.
        vm.pullRequests.detail = nil
        vm.pullRequests.commits = []
        vm.pullRequests.files = []
        vm.pullRequests.detailError = "stale error"
        let beforeGen = vm.pullRequests.detailGen

        vm.pullRequests.select(Self.pr(42))

        #expect(vm.pullRequests.selected?.number == 42)
        #expect(vm.pullRequests.detail == nil)
        #expect(vm.pullRequests.commits.isEmpty)
        #expect(vm.pullRequests.files.isEmpty)
        #expect(vm.pullRequests.detailError == nil)
        #expect(vm.pullRequests.detailGen == beforeGen &+ 1)
    }

    @Test("closeDetail clears state and bumps the gen-token")
    func closeClearsAndBumps() {
        let vm = Self.makeVM()
        vm.pullRequests.selected = Self.pr(42)
        vm.pullRequests.detailError = "old"
        let beforeGen = vm.pullRequests.detailGen

        vm.pullRequests.closeDetail()

        #expect(vm.pullRequests.selected == nil)
        #expect(vm.pullRequests.detail == nil)
        #expect(vm.pullRequests.commits.isEmpty)
        #expect(vm.pullRequests.files.isEmpty)
        #expect(vm.pullRequests.detailError == nil)
        #expect(vm.pullRequests.detailGen == beforeGen &+ 1)
    }

    @Test("loadDetail short-circuits when no PR is selected")
    func loadDetailNoPR() async {
        let vm = Self.makeVM()
        // Bump once to detect the early-return: the function bumps the token
        // before it can short-circuit on the missing PR.
        let beforeGen = vm.pullRequests.detailGen
        await vm.pullRequests.loadDetail()
        #expect(vm.pullRequests.detailGen == beforeGen &+ 1)
        #expect(vm.pullRequests.detail == nil)
        #expect(vm.pullRequests.detailError == nil)
    }
}

@Suite("RepositoryViewModel — local PR merge guards", .serialized)
@MainActor
struct RepositoryViewModelPullMergeGuardsTests {

    private static func makeVM() -> RepositoryViewModel {
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        return RepositoryViewModel(repository: Repository(url: url))
    }

    private static func pr() -> PullRequest {
        PullRequest(
            id: "1", number: 1, title: "T", state: .open,
            authorLogin: nil, authorAvatarURL: nil,
            sourceBranch: "feature/x", targetBranch: "main",
            webURL: nil, createdAt: nil, updatedAt: nil
        )
    }

    @Test("attemptLocalMergeForPullRequest fails when no PR is selected")
    func failsWithoutSelection() async {
        let vm = Self.makeVM()
        let outcome = await vm.attemptLocalMergeForPullRequest()
        guard case .failed(let message) = outcome else {
            Issue.record("Expected .failed, got \(outcome)")
            return
        }
        #expect(message.contains("No pull request"))
    }

    @Test("attemptLocalMergeForPullRequest fails when another local merge is already running")
    func failsWhenAlreadyRunning() async {
        let vm = Self.makeVM()
        vm.pullRequests.selected = Self.pr()
        vm.pullRequests.localMergeRunning = true
        let outcome = await vm.attemptLocalMergeForPullRequest()
        guard case .failed(let message) = outcome else {
            Issue.record("Expected .failed, got \(outcome)")
            return
        }
        #expect(message.contains("already running"))
    }

    @Test("attemptLocalMergeForPullRequest fails when a merge or rebase is in progress")
    func failsWhenMergeInProgress() async {
        let vm = Self.makeVM()
        vm.pullRequests.selected = Self.pr()
        vm.mergeState = .merging
        let outcome = await vm.attemptLocalMergeForPullRequest()
        guard case .failed(let message) = outcome else {
            Issue.record("Expected .failed, got \(outcome)")
            return
        }
        #expect(message.contains("merge or rebase"))
        // Guard ran before localMergeRunning was flipped.
        #expect(vm.pullRequests.localMergeRunning == false)
    }

    @Test("attemptLocalMergeForPullRequest fails when working tree is dirty")
    func failsWhenDirty() async {
        let vm = Self.makeVM()
        vm.pullRequests.selected = Self.pr()
        let dirty = WorkingCopyFile(
            path: "README.md",
            stagedStatus: .unmodified,
            unstagedStatus: .modified,
            originalPath: nil
        )
        vm.status = WorkingCopyStatus(files: [dirty])
        let outcome = await vm.attemptLocalMergeForPullRequest()
        guard case .failed(let message) = outcome else {
            Issue.record("Expected .failed, got \(outcome)")
            return
        }
        #expect(message.contains("uncommitted"))
        #expect(vm.pullRequests.localMergeRunning == false)
    }
}

@Suite("PullRequestStore — list throttle", .serialized)
@MainActor
struct RepositoryViewModelPullListTests {

    private static func makeVM() -> RepositoryViewModel {
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        return RepositoryViewModel(repository: Repository(url: url))
    }

    @Test("load short-circuits inside the 30s throttle window when not forced")
    func throttlesUnforced() async {
        let vm = Self.makeVM()
        vm.pullRequests.lastLoadedAt = .now
        // Pre-seed an error so we can detect that the function bailed before
        // touching anything (it would clear `error` on entry).
        vm.pullRequests.error = "sentinel"
        await vm.pullRequests.load()
        #expect(vm.pullRequests.error == "sentinel")
        #expect(vm.pullRequests.isLoading == false)
    }

    @Test("load is a no-op when another load is already in flight")
    func noOpWhenAlreadyLoading() async {
        let vm = Self.makeVM()
        vm.pullRequests.isLoading = true
        vm.pullRequests.error = "sentinel"
        await vm.pullRequests.load(force: true)
        #expect(vm.pullRequests.error == "sentinel")
        #expect(vm.pullRequests.isLoading == true)
    }

    @Test("closeDetail clears the loading flag of the invalidated load")
    func closeClearsLoadingFlag() {
        let vm = Self.makeVM()
        vm.pullRequests.isLoadingDetail = true
        vm.pullRequests.closeDetail()
        #expect(vm.pullRequests.isLoadingDetail == false)
    }

    @Test("reset drops list and detail state")
    func resetDropsEverything() {
        let vm = Self.makeVM()
        vm.pullRequests.items = PullRequest.previewSamples
        vm.pullRequests.host = .previewGitHub
        vm.pullRequests.requiresToken = true
        vm.pullRequests.lastLoadedAt = .now
        vm.pullRequests.reset()
        #expect(vm.pullRequests.items.isEmpty)
        #expect(vm.pullRequests.host == nil)
        #expect(vm.pullRequests.requiresToken == false)
        #expect(vm.pullRequests.lastLoadedAt == nil)
    }
}
