import Foundation

/// Cherry-pick / revert / reset wired into `RepositoryViewModel`.
/// Each method returns an `IntegrationOutcome` so the view can decide whether
/// to celebrate, route to the conflict resolver, or surface the error.
extension RepositoryViewModel {
    func cherryPick(_ commit: Commit) async -> IntegrationOutcome {
        commitError = nil
        let mainline = commit.isMerge ? 1 : nil
        do {
            try await cli.cherryPick(sha: commit.sha, mainline: mainline)
            await refreshAfterIntegration()
            return .clean
        } catch {
            await refreshAfterIntegration()
            // cherry-pick may pause without setting MERGE_HEAD; check both
            // `mergeState` and unmerged paths so the resolver still opens.
            if mergeState.isInProgress || !conflictFiles.isEmpty {
                return .conflicts
            }
            let message = error.userMessage
            commitError = message
            return .failed(message)
        }
    }

    func revert(_ commit: Commit) async -> IntegrationOutcome {
        commitError = nil
        let mainline = commit.isMerge ? 1 : nil
        do {
            try await cli.revert(sha: commit.sha, mainline: mainline)
            await refreshAfterIntegration()
            return .clean
        } catch {
            await refreshAfterIntegration()
            if mergeState.isInProgress || !conflictFiles.isEmpty {
                return .conflicts
            }
            let message = error.userMessage
            commitError = message
            return .failed(message)
        }
    }

    func reset(to sha: String, mode: GitCLI.ResetMode) async -> IntegrationOutcome {
        commitError = nil
        do {
            try await cli.reset(to: sha, mode: mode)
            await refreshAfterIntegration()
            return .clean
        } catch {
            await refreshAfterIntegration()
            let message = error.userMessage
            commitError = message
            return .failed(message)
        }
    }
}
