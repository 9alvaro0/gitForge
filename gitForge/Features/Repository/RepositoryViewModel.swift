import Foundation
import Observation
import os

@Observable
@MainActor
final class RepositoryViewModel {
    static let pageSize = 200

    private static let logger = Logger(subsystem: "com.warwarelabs.gitForge", category: "repo-vm")

    let repository: Repository

    private(set) var commits: [Commit] = []
    private(set) var isLoadingInitial = false
    private(set) var isLoadingMore = false
    private(set) var hasMore = true
    var loadError: String?

    var selectedCommitId: Commit.ID?

    private(set) var detailCache: [String: CommitDetail] = [:]
    private(set) var loadingDetailFor: String?

    private(set) var refs: [GitRef] = []
    private(set) var currentBranchName: String?

    private(set) var graphLayouts: [GraphRowLayout] = []
    private(set) var graphMaxLanes: Int = 1

    private(set) var status: WorkingCopyStatus = WorkingCopyStatus(files: [])
    private(set) var isLoadingStatus = false
    var commitSubject: String = ""
    var commitBody: String = ""
    var amendMode: Bool = false {
        didSet {
            guard oldValue != amendMode, amendMode else {
                if !amendMode {
                    commitSubject = ""
                    commitBody = ""
                }
                return
            }
            Task { await prefillFromHead() }
        }
    }
    var commitError: String?

    /// Path of the file selected inside the current commit's detail panel.
    var selectedCommitFile: String? {
        didSet {
            guard oldValue != selectedCommitFile else { return }
            if let path = selectedCommitFile, let commit = selectedCommit {
                Task { await loadCommitFileDiff(sha: commit.sha, path: path) }
            }
        }
    }
    private(set) var commitFileDiff: [DiffHunk] = []
    private(set) var loadingCommitFileDiff = false

    /// Selected file in the working-copy view (Changes tab).
    var selectedWorkingCopyFile: WorkingCopyFile? {
        didSet {
            guard oldValue != selectedWorkingCopyFile else { return }
            if let file = selectedWorkingCopyFile {
                Task { await loadWorkingCopyDiff(file: file) }
            } else {
                workingCopyDiff = []
            }
        }
    }
    private(set) var workingCopyDiff: [DiffHunk] = []
    private(set) var loadingWorkingCopyDiff = false

    enum RemoteOperation: Sendable, Equatable { case fetching, pulling, pushing }
    var remoteOperation: RemoteOperation?
    var remoteFailure: RemoteFailure?
    private(set) var upstream: String?
    private(set) var aheadCount: Int = 0
    private(set) var behindCount: Int = 0
    private(set) var lastFetchedAt: Date?

    /// `nil` filter shows the current HEAD branch.
    var selectedFilterBranch: String? {
        didSet {
            guard oldValue != selectedFilterBranch else { return }
            Task { await reloadAfterFilterChange() }
        }
    }

    private let cli: GitCLI

    init(repository: Repository) {
        self.repository = repository
        self.cli = GitCLI(workingDirectory: repository.url)
    }

    func loadInitial() async {
        guard commits.isEmpty, !isLoadingInitial else { return }
        isLoadingInitial = true
        defer { isLoadingInitial = false }
        do {
            let page = try await cli.log(branch: filterBranchForLog, limit: Self.pageSize, skip: 0)
            commits = page
            hasMore = page.count == Self.pageSize
            selectedCommitId = page.first?.id
            recomputeGraph()
        } catch {
            Self.logger.error("Failed to load log: \(error.localizedDescription, privacy: .public)")
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func loadMoreIfNeeded(currentItem: Commit) async {
        guard hasMore, !isLoadingMore else { return }
        guard let last = commits.last, last.id == currentItem.id else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let next = try await cli.log(branch: filterBranchForLog, limit: Self.pageSize, skip: commits.count)
            commits.append(contentsOf: next)
            hasMore = next.count == Self.pageSize
            recomputeGraph()
        } catch {
            Self.logger.error("Failed to load more: \(error.localizedDescription, privacy: .public)")
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func recomputeGraph() {
        let result = GraphLayoutEngine.layouts(for: commits)
        graphLayouts = result.rows
        graphMaxLanes = max(1, result.maxLanes)
    }

    func loadRefs() async {
        async let refsTask: [GitRef]? = try? cli.refs()
        async let currentTask: String? = cli.currentBranchName()
        if let refs = await refsTask {
            self.refs = refs
        }
        if let current = await currentTask {
            self.currentBranchName = current
        }
        await loadAheadBehind()
    }

    func refreshStatus() async {
        isLoadingStatus = true
        defer { isLoadingStatus = false }
        do {
            status = try await cli.status()
        } catch {
            Self.logger.error("Failed to load status: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stage(_ files: [WorkingCopyFile]) async {
        await runStageOperation { try await self.cli.stage(paths: files.map(\.path)) }
    }

    func unstage(_ files: [WorkingCopyFile]) async {
        await runStageOperation { try await self.cli.unstage(paths: files.map(\.path)) }
    }

    func discardChanges(_ files: [WorkingCopyFile]) async {
        let tracked = files.filter { !$0.isUntracked }
        let untracked = files.filter(\.isUntracked)
        await runStageOperation {
            try await self.cli.discardChanges(paths: tracked.map(\.path))
            try await self.cli.deleteUntracked(paths: untracked.map(\.path))
        }
    }

    private func runStageOperation(_ block: () async throws -> Void) async {
        do {
            try await block()
            await refreshStatus()
        } catch {
            Self.logger.error("Stage operation failed: \(error.localizedDescription, privacy: .public)")
            commitError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func commit() async -> Bool {
        let subject = commitSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subject.isEmpty else {
            commitError = "Commit subject cannot be empty"
            return false
        }
        guard amendMode || status.hasStagedChanges else {
            commitError = "Nothing staged to commit"
            return false
        }
        do {
            try await cli.commit(
                subject: subject,
                body: commitBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : commitBody,
                amend: amendMode
            )
            commitSubject = ""
            commitBody = ""
            amendMode = false
            commitError = nil
            await refreshStatus()
            await loadRefs()
            // Force a fresh log read so HEAD shows the new commit
            commits = []
            graphLayouts = []
            graphMaxLanes = 1
            hasMore = true
            selectedCommitId = nil
            await loadInitial()
            return true
        } catch {
            Self.logger.error("Commit failed: \(error.localizedDescription, privacy: .public)")
            commitError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    private func prefillFromHead() async {
        do {
            let result = try await cli.run(["log", "-1", "HEAD", "--format=%B"])
            let message = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if let firstNewline = message.firstIndex(of: "\n") {
                commitSubject = String(message[..<firstNewline])
                commitBody = String(message[message.index(after: firstNewline)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                commitSubject = message
                commitBody = ""
            }
        } catch {
            Self.logger.error("Failed to read HEAD message: \(error.localizedDescription, privacy: .public)")
        }
    }

    func createBranch(name: String, startingAt: String? = nil, checkout: Bool) async -> Result<Void, Error> {
        do {
            try await cli.createBranch(name, startingAt: startingAt, checkout: checkout)
            await refreshAfterRefMutation(reloadLog: checkout)
            return .success(())
        } catch {
            Self.logger.error("Failed to create branch \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    func checkoutBranch(_ ref: GitRef) async -> Result<Void, Error> {
        let target = ref.isLocalBranch ? ref.name : ref.displayName
        do {
            try await cli.checkout(branch: target)
            await refreshAfterRefMutation(reloadLog: true)
            return .success(())
        } catch {
            Self.logger.error("Failed to checkout \(target, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    func deleteBranch(_ ref: GitRef, force: Bool = false) async -> Result<Void, Error> {
        do {
            try await cli.deleteBranch(ref.name, force: force)
            await refreshAfterRefMutation(reloadLog: false)
            return .success(())
        } catch {
            Self.logger.error("Failed to delete branch \(ref.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    func renameBranch(from oldName: String, to newName: String) async -> Result<Void, Error> {
        do {
            try await cli.renameBranch(from: oldName, to: newName)
            await refreshAfterRefMutation(reloadLog: false)
            return .success(())
        } catch {
            Self.logger.error("Failed to rename \(oldName, privacy: .public) to \(newName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    private func refreshAfterRefMutation(reloadLog: Bool) async {
        await loadRefs()
        await refreshStatus()
        if reloadLog {
            commits = []
            graphLayouts = []
            graphMaxLanes = 1
            hasMore = true
            selectedCommitId = nil
            await loadInitial()
        }
    }

    func loadAheadBehind() async {
        upstream = await cli.upstreamName()
        guard let upstream, let branch = currentBranchName else {
            aheadCount = 0
            behindCount = 0
            return
        }
        do {
            let counts = try await cli.aheadBehind(branch: branch, upstream: upstream)
            aheadCount = counts.ahead
            behindCount = counts.behind
        } catch {
            aheadCount = 0
            behindCount = 0
        }
    }

    func fetch() async {
        guard remoteOperation == nil else { return }
        remoteOperation = .fetching
        defer { remoteOperation = nil }
        do {
            try await cli.fetchAll()
            lastFetchedAt = .now
            await loadRefs()
            await loadAheadBehind()
        } catch {
            remoteFailure = RemoteFailure.from(error)
        }
    }

    func pull() async {
        guard remoteOperation == nil else { return }
        remoteOperation = .pulling
        defer { remoteOperation = nil }
        do {
            try await cli.pull()
            commits = []
            graphLayouts = []
            graphMaxLanes = 1
            hasMore = true
            selectedCommitId = nil
            await loadInitial()
            await loadRefs()
            await refreshStatus()
            await loadAheadBehind()
        } catch {
            remoteFailure = RemoteFailure.from(error)
        }
    }

    func push() async {
        guard remoteOperation == nil else { return }
        remoteOperation = .pushing
        defer { remoteOperation = nil }
        let setUpstream = upstream == nil
        do {
            try await cli.push(setUpstream: setUpstream, branch: currentBranchName)
            if setUpstream { upstream = await cli.upstreamName() }
            await loadRefs()
            await loadAheadBehind()
        } catch {
            remoteFailure = RemoteFailure.from(error)
        }
    }

    func loadCommitFileDiff(sha: String, path: String) async {
        loadingCommitFileDiff = true
        defer { loadingCommitFileDiff = false }
        do {
            let raw = try await cli.diff(sha: sha, file: path)
            commitFileDiff = DiffParser.parse(raw)
        } catch {
            Self.logger.error("Failed to load commit diff: \(error.localizedDescription, privacy: .public)")
            commitFileDiff = []
        }
    }

    func loadWorkingCopyDiff(file: WorkingCopyFile) async {
        loadingWorkingCopyDiff = true
        defer { loadingWorkingCopyDiff = false }
        do {
            let raw: String
            if file.isStaged {
                raw = try await cli.diffStaged(file: file.path)
            } else if file.isUntracked {
                raw = ""
            } else {
                raw = try await cli.diffUnstaged(file: file.path)
            }
            workingCopyDiff = DiffParser.parse(raw)
        } catch {
            Self.logger.error("Failed to load working-copy diff: \(error.localizedDescription, privacy: .public)")
            workingCopyDiff = []
        }
    }

    func detail(for commit: Commit) async -> CommitDetail? {
        if let cached = detailCache[commit.sha] { return cached }
        loadingDetailFor = commit.sha
        defer { if loadingDetailFor == commit.sha { loadingDetailFor = nil } }
        do {
            let detail = try await cli.commitDetail(for: commit)
            detailCache[commit.sha] = detail
            return detail
        } catch {
            Self.logger.error("Failed to load detail for \(commit.sha, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    var selectedCommit: Commit? {
        guard let id = selectedCommitId else { return nil }
        return commits.first { $0.id == id }
    }

    var refsBySha: [String: [GitRef]] {
        Dictionary(grouping: refs) { $0.targetSha }
    }

    var localBranches: [GitRef] {
        refs.filter(\.isLocalBranch).sorted { $0.name < $1.name }
    }

    var remoteBranches: [GitRef] {
        refs.filter(\.isRemoteBranch).sorted { $0.name < $1.name }
    }

    var tags: [GitRef] {
        refs.filter(\.isTag).sorted { $0.name < $1.name }
    }

    /// Branch name passed to `git log`. `--all` is special-cased.
    private var filterBranchForLog: String? {
        switch selectedFilterBranch {
        case nil: nil
        case "ALL": "--all"
        case .some(let value): value
        }
    }

    /// Resets commits and reloads with the new filter.
    private func reloadAfterFilterChange() async {
        commits = []
        graphLayouts = []
        graphMaxLanes = 1
        hasMore = true
        selectedCommitId = nil
        loadError = nil
        await loadInitial()
    }
}

extension RepositoryViewModel {
    static var preview: RepositoryViewModel {
        let vm = RepositoryViewModel(repository: Repository.preview)
        vm.commits = Commit.previewSamples
        vm.selectedCommitId = Commit.previewSamples.first?.id
        vm.detailCache[Commit.preview.sha] = CommitDetail.preview
        vm.refs = GitRef.previewSamples
        vm.currentBranchName = "main"
        vm.status = WorkingCopyStatus.preview
        vm.recomputeGraph()
        return vm
    }
}
