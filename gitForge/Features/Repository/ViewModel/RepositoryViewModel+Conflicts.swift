import Foundation
import os

/// Conflict-resolution state on top of `RepositoryViewModel`.
extension RepositoryViewModel {
    /// Sides supported when resolving an entire conflicted file in one shot.
    /// `.both` only makes sense per-hunk so it stays in `ConflictHunk.Pick`,
    /// not here.
    enum WholeFilePick: Sendable, Equatable { case ours, theirs }

    /// Reads the integration state and, when one is in progress, refreshes
    /// the resolver (`conflicts`) from the unmerged paths.
    func loadConflictState() async {
        mergeState = await cli.mergeState()
        if mergeState != .unmerged {
            conflictedStashSha = nil
        }
        guard mergeState.isInProgress else {
            conflicts.clear()
            return
        }
        do {
            await conflicts.reload(unmergedPaths: try await cli.unmergedPaths())
        } catch {
            // Underlying `git diff --diff-filter=U` failure is logged by GitCLI.
        }
    }

    /// Replaces the file content with one whole side and stages it. Used by
    /// the "Resolve using ours/theirs" context menu in `ConflictView`.
    func resolveFile(at path: String, using side: WholeFilePick) async {
        await runConflictMutation {
            switch side {
            case .ours:   try await self.cli.checkoutOurs(path: path)
            case .theirs: try await self.cli.checkoutTheirs(path: path)
            }
            try await self.cli.markResolved(path: path)
        }
    }

    /// Applies the user's per-hunk picks to the selected file (keeping its
    /// encoding) and stages it.
    func resolveSelectedFile() async {
        await runConflictMutation {
            guard let path = try await self.conflicts.writeResolution() else { return }
            try await self.cli.markResolved(path: path)
        }
    }

    /// Resolution steps write the index, so they hold `isMutating` like every
    /// other local mutation: the watcher is suspended and a double click (or
    /// a commit racing it) can't fight over `.git/index.lock`.
    private func runConflictMutation(_ body: () async throws -> Void) async {
        guard !isMutating else {
            commitError = "Another operation is in progress."
            return
        }
        isMutating = true
        defer { isMutating = false }
        do {
            try await body()
        } catch {
            commitError = error.userMessage
        }
        await loadConflictState()
        await refreshStatus()
    }

    /// Drops the in-progress integration and returns the worktree to clean.
    /// `.unmerged` (stash apply) and `.bisecting` don't go through here —
    /// stash has its own `abortStashApply`; bisect needs `git bisect reset`
    /// and is exposed separately.
    func abortMerge() async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            switch mergeState {
            case .merging:        try await cli.mergeAbort()
            case .rebasing:       try await cli.rebaseAbort()
            case .cherryPicking:  try await cli.cherryPickAbort()
            case .reverting:      try await cli.revertAbort()
            case .clean, .unmerged, .bisecting: return
            }
            await refreshAfterIntegration()
        } catch {
            commitError = error.userMessage
        }
    }

    /// Outcome of an integration op (merge / rebase / cherry-pick). Encodes
    /// whether the op finished cleanly, paused on conflicts, or failed.
    enum IntegrationOutcome: Sendable, Equatable {
        case clean
        case conflicts
        case failed(String)
    }

    /// Convenience: merge `source` into the currently checked-out branch.
    func mergeBranch(_ source: GitRef) async -> IntegrationOutcome {
        await mergeBranch(source: source, into: nil)
    }

    /// Merges `source` into `target`. If `target` is nil or already current,
    /// behaves like a direct `git merge`. Otherwise checks out `target` first
    /// so the merge lands on the right ref.
    func mergeBranch(source: GitRef, into target: GitRef?) async -> IntegrationOutcome {
        guard !isMutating else { return .failed("Another operation is in progress.") }
        let sourceName = source.isLocalBranch ? source.name : source.displayName
        isMutating = true
        defer { isMutating = false }
        do {
            if let target, target.name != currentBranchName {
                guard target.isLocalBranch else {
                    return .failed("Can only merge into a local branch.")
                }
                try await cli.checkout(branch: target.name)
                await refreshAfterRefMutation(reloadLog: true)
            }
            try await cli.merge(branch: sourceName)
            await refreshAfterIntegration()
            return .clean
        } catch {
            await refreshAfterIntegration()
            if mergeState.isInProgress {
                return .conflicts
            }
            let message = error.userMessage
            commitError = message
            return .failed(message)
        }
    }

    /// `git rebase <upstream>` against the current HEAD. Routes conflicts to
    /// the resolver via the `IntegrationOutcome`.
    func rebaseOnto(_ ref: GitRef) async -> IntegrationOutcome {
        guard !isMutating else { return .failed("Another operation is in progress.") }
        let upstream = ref.isLocalBranch ? ref.name : ref.displayName
        isMutating = true
        defer { isMutating = false }
        do {
            try await cli.rebase(onto: upstream)
            await refreshAfterIntegration()
            return .clean
        } catch {
            await refreshAfterIntegration()
            if mergeState.isInProgress {
                return .conflicts
            }
            let message = error.userMessage
            commitError = message
            return .failed(message)
        }
    }

    /// Continues a paused merge or rebase. `.unmerged` has no continue command —
    /// once everything is staged the user just commits; we still refresh so
    /// the UI catches up either way.
    func continueMerge() async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            switch mergeState {
            case .merging:        try await cli.mergeContinue()
            case .rebasing:       try await cli.rebaseContinue()
            case .cherryPicking:  try await cli.cherryPickContinue()
            case .reverting:      try await cli.revertContinue()
            case .clean, .unmerged, .bisecting: break
            }
            await refreshAfterIntegration()
        } catch {
            commitError = error.userMessage
        }
    }

    /// `loadConflictState`, `refreshStatus` and `loadRefs` are independent so
    /// they run in parallel; only `reloadLog` waits on the fresh refs (its
    /// graphScope reads `unmergedLocalBranchRefs` and `stashes`).
    /// Shared with `+Operations` so cherry-pick / revert / reset get the
    /// same parallel refresh as merge / rebase.
    func refreshAfterIntegration() async {
        async let conflicts: Void = loadConflictState()
        async let status: Void = refreshStatus()
        async let refs: Void = loadRefs()
        _ = await (conflicts, status, refs)
        await reloadLog()
    }
}
