import Foundation
import Observation
import os

@Observable
@MainActor
final class RepositoryViewModel {
    static let pageSize = 200
    static let maxRevealPages = 10

    static let logger = Logger(subsystem: "com.warwarelabs.gitForge", category: "repo-vm")

    let repository: Repository
    let cli: GitCLI

    // MARK: Log
    var commits: [Commit] = []
    var isLoadingInitial = false
    var isLoadingMore = false
    var hasMore = true
    var loadError: String?

    var selectedCommitId: Commit.ID?

    // MARK: Detail
    var detailCache: [String: CommitDetail] = [:]
    var loadingDetailFor: String?

    // MARK: Refs / branches / stashes
    var refs: [GitRef] = []
    var currentBranchName: String?
    var stashes: [Stash] = []

    // MARK: Graph
    var graphLayouts: [GraphRowLayout] = []
    var graphMaxLanes: Int = 1

    // MARK: Working copy
    var status: WorkingCopyStatus = WorkingCopyStatus(files: [])
    var isLoadingStatus = false
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

    // MARK: Diffs
    var selectedCommitFile: String? {
        didSet {
            guard oldValue != selectedCommitFile else { return }
            if let path = selectedCommitFile, let commit = selectedCommit {
                Task { await loadCommitFileDiff(sha: commit.sha, path: path) }
            }
        }
    }
    var commitFileDiff: [DiffHunk] = []
    var loadingCommitFileDiff = false

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
    var workingCopyDiff: [DiffHunk] = []
    var loadingWorkingCopyDiff = false

    // MARK: Navigation
    var scrollTargetSha: String?
    var isRevealingCommit = false

    // MARK: Remote
    enum RemoteOperation: Sendable, Equatable { case fetching, pulling, pushing }
    var remoteOperation: RemoteOperation?
    var remoteFailure: RemoteFailure?
    var upstream: String?
    var aheadCount: Int = 0
    var behindCount: Int = 0
    var lastFetchedAt: Date?

    init(repository: Repository) {
        self.repository = repository
        self.cli = GitCLI(workingDirectory: repository.url)
    }

    // MARK: Computed views

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
}

// MARK: - Preview

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
