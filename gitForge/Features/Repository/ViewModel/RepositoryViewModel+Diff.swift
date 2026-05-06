import Foundation
import os

extension RepositoryViewModel {
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
}
