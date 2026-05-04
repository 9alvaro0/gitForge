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
            let page = try await cli.log(limit: Self.pageSize, skip: 0)
            commits = page
            hasMore = page.count == Self.pageSize
            selectedCommitId = page.first?.id
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
            let next = try await cli.log(limit: Self.pageSize, skip: commits.count)
            commits.append(contentsOf: next)
            hasMore = next.count == Self.pageSize
        } catch {
            Self.logger.error("Failed to load more: \(error.localizedDescription, privacy: .public)")
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
}

extension RepositoryViewModel {
    static var preview: RepositoryViewModel {
        let vm = RepositoryViewModel(repository: Repository.preview)
        vm.commits = Commit.previewSamples
        vm.selectedCommitId = Commit.previewSamples.first?.id
        vm.detailCache[Commit.preview.sha] = CommitDetail.preview
        return vm
    }
}
