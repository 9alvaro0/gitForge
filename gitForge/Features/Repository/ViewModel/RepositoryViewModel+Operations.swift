import Foundation

/// Cherry-pick / revert / reset wired into `RepositoryViewModel`. A reset
/// offers its undo (`undo.pending`).
/// Each method returns an `IntegrationOutcome` so the view can decide whether
/// to celebrate, route to the conflict resolver, or surface the error.
extension RepositoryViewModel {
    func cherryPick(_ commit: Commit) async -> IntegrationOutcome {
        guard !isMutating else { return .failed(String(localized: "Another operation is in progress.")) }
        commitError = nil
        let mainline = commit.isMerge ? 1 : nil
        isMutating = true
        defer { isMutating = false }
        do {
            try await cli.cherryPick(sha: commit.sha, mainline: mainline)
            await refreshAfterIntegration()
            return .clean
        } catch {
            await refreshAfterIntegration()
            // cherry-pick may pause without setting MERGE_HEAD; check both
            // `mergeState` and unmerged paths so the resolver still opens.
            if mergeState.isInProgress || !conflicts.files.isEmpty {
                return .conflicts
            }
            let message = error.userMessage
            commitError = message
            return .failed(message)
        }
    }

    func revert(_ commit: Commit) async -> IntegrationOutcome {
        guard !isMutating else { return .failed(String(localized: "Another operation is in progress.")) }
        commitError = nil
        let mainline = commit.isMerge ? 1 : nil
        isMutating = true
        defer { isMutating = false }
        do {
            try await cli.revert(sha: commit.sha, mainline: mainline)
            await refreshAfterIntegration()
            return .clean
        } catch {
            await refreshAfterIntegration()
            if mergeState.isInProgress || !conflicts.files.isEmpty {
                return .conflicts
            }
            let message = error.userMessage
            commitError = message
            return .failed(message)
        }
    }

    func reset(to sha: String, mode: GitCLI.ResetMode) async -> IntegrationOutcome {
        guard !isMutating else { return .failed(String(localized: "Another operation is in progress.")) }
        commitError = nil
        isMutating = true
        defer { isMutating = false }
        // Read before the reset: HEAD, its branch, and the index and
        // worktree a mixed or hard reset is about to drop.
        let capture = await cli.captureReset(mode: mode)
        do {
            try await cli.reset(to: sha, mode: mode)
            if let capture { undo.record(await cli.resetUndo(after: capture)) }
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
