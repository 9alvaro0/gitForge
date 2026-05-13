import Foundation

extension RepositoryViewModel {
    func stashAll(message: String? = nil) async -> Result<Void, Error> {
        guard !isMutating else { return .failure(GitError.busy) }
        guard !status.isClean else {
            return .failure(StashError.nothingToStash)
        }
        isMutating = true
        defer { isMutating = false }
        do {
            try await cli.stashPush(message: message,
                                    includeUntracked: AppTheme.persistedStashIncludeUntracked())
            // refreshAfterIntegration also reloads the log, which is what
            // surfaces the new dashed stash dot in the graph — without it
            // the row only appeared on the next external refresh.
            await refreshAfterIntegration()
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    /// Apply (and optionally drop) a stash. Returns an `IntegrationOutcome` so
    /// the view can route conflicts to the resolver UI an  d surface friendly
    /// messages for the common pre-flight abort cases (dirty worktree).
    func applyStash(_ stash: Stash, drop: Bool) async -> IntegrationOutcome {
        guard !isMutating else { return .failed("Another operation is in progress.") }
        isMutating = true
        defer { isMutating = false }
        do {
            try await cli.stashApply(index: stash.index, drop: drop)
            await refreshAfterIntegration()
            return .clean
        } catch {
            // `git stash apply/pop` with conflicts exits non-zero but leaves
            // unmerged paths in the worktree (no MERGE_HEAD). Our `mergeState`
            // detects this as `.unmerged`, so the same conflict resolver
            // pipeline used by merge/rebase covers stash apply too. `pop`
            // preserves the stash automatically when there are conflicts.
            await refreshAfterIntegration()
            if mergeState.isInProgress {
                return .conflicts
            }
            return .failed(friendlyStashApplyMessage(for: error))
        }
    }

    /// Recovery path for a `git stash apply/pop` that left the worktree in
    /// `.unmerged`. Resets the tree to HEAD; the stash entry stays in the list
    /// (pop only drops on clean apply) so the user can retry once HEAD is
    /// ready for it.
    func abortStashApply() async -> Result<Void, Error> {
        guard !isMutating else { return .failure(GitError.busy) }
        isMutating = true
        defer { isMutating = false }
        do {
            try await cli.stashAbortApply()
            await refreshAfterIntegration()
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func dropStash(_ stash: Stash) async -> Result<Void, Error> {
        guard !isMutating else { return .failure(GitError.busy) }
        isMutating = true
        defer { isMutating = false }
        do {
            try await cli.stashDrop(index: stash.index)
            // Dropping a stash leaves its dashed-dot row in `commits` until
            // a reloadLog runs — `refreshAfterIntegration` does that, so
            // the phantom row disappears immediately.
            await refreshAfterIntegration()
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    private func friendlyStashApplyMessage(for error: Error) -> String {
        let raw = error.userMessage
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
