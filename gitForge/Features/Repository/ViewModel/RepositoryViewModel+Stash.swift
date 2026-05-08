import Foundation
import os

extension RepositoryViewModel {
    func stashAll(message: String? = nil) async -> Result<Void, Error> {
        guard !status.isClean else {
            return .failure(StashError.nothingToStash)
        }
        do {
            try await cli.stashPush(message: message, includeUntracked: true)
            await loadRefs()
            await refreshStatus()
            return .success(())
        } catch {
            Self.logger.error("Stash push failed: \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    /// Apply (and optionally drop) a stash. Returns an `IntegrationOutcome` so
    /// the view can route conflicts to the resolver UI and surface friendly
    /// messages for the common pre-flight abort cases (dirty worktree).
    func applyStash(_ stash: Stash, drop: Bool) async -> IntegrationOutcome {
        do {
            try await cli.stashApply(index: stash.index, drop: drop)
            await loadRefs()
            await refreshStatus()
            await loadConflictState()
            return .clean
        } catch {
            Self.logger.error("Stash apply failed: \(error.localizedDescription, privacy: .public)")
            await loadRefs()
            await refreshStatus()
            // `git stash apply/pop` with conflicts exits non-zero but leaves
            // unmerged paths in the worktree (no MERGE_HEAD). Our `mergeState`
            // detects this as `.unmerged`, so the same conflict resolver
            // pipeline used by merge/rebase covers stash apply too. `pop`
            // preserves the stash automatically when there are conflicts.
            await loadConflictState()
            if mergeState.isInProgress {
                return .conflicts
            }
            return .failed(friendlyStashApplyMessage(for: error))
        }
    }

    func dropStash(_ stash: Stash) async -> Result<Void, Error> {
        do {
            try await cli.stashDrop(index: stash.index)
            await loadRefs()
            return .success(())
        } catch {
            Self.logger.error("Stash drop failed: \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    private func friendlyStashApplyMessage(for error: Error) -> String {
        let raw = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if raw.contains("would be overwritten") {
            return "Commit, stash, or discard your current changes before applying this stash."
        }
        return raw
    }
}

enum StashError: LocalizedError {
    case nothingToStash

    var errorDescription: String? {
        switch self {
        case .nothingToStash: "No changes to stash"
        }
    }
}
