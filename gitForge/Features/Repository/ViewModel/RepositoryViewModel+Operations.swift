import Foundation
import os

/// Cherry-pick / revert / reset wired into `RepositoryViewModel`.
/// Each method returns an `IntegrationOutcome` so the view can decide whether
/// to celebrate, route to the conflict resolver, or surface the error.
extension RepositoryViewModel {
    func cherryPick(_ commit: Commit) async -> IntegrationOutcome {
        let mainline = commit.isMerge ? 1 : nil
        do {
            try await cli.cherryPick(sha: commit.sha, mainline: mainline)
            await refreshAfterRefMutation(reloadLog: true)
            await loadConflictState()
            return .clean
        } catch {
            await loadConflictState()
            await refreshStatus()
            if mergeState.isInProgress {
                return .conflicts
            }
            // cherry-pick may pause without triggering MERGE_HEAD; check unmerged paths.
            if !conflictFiles.isEmpty {
                return .conflicts
            }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            commitError = message
            return .failed(message)
        }
    }

    func revert(_ commit: Commit) async -> IntegrationOutcome {
        let mainline = commit.isMerge ? 1 : nil
        do {
            try await cli.revert(sha: commit.sha, mainline: mainline)
            await refreshAfterRefMutation(reloadLog: true)
            return .clean
        } catch {
            await refreshStatus()
            await loadConflictState()
            if !conflictFiles.isEmpty {
                return .conflicts
            }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            commitError = message
            return .failed(message)
        }
    }

    func reset(to sha: String, mode: GitCLI.ResetMode) async -> IntegrationOutcome {
        do {
            try await cli.reset(to: sha, mode: mode)
            await refreshAfterRefMutation(reloadLog: true)
            return .clean
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            commitError = message
            return .failed(message)
        }
    }
}
