import Foundation
import os

/// Conflict-resolution state on top of `RepositoryViewModel`.
extension RepositoryViewModel {
    func loadConflictState() async {
        mergeState = await cli.mergeState()
        guard mergeState.isInProgress else {
            conflictFiles = []
            conflictHunks = []
            return
        }
        do {
            let paths = try await cli.unmergedPaths()
            var entries: [ConflictFile] = []
            for path in paths {
                let absolute = repository.url.appendingPathComponent(path)
                let resolved = (try? String(contentsOf: absolute, encoding: .utf8))
                    .map { ConflictParser.parse($0).hunks.isEmpty } ?? true
                let count = (try? String(contentsOf: absolute, encoding: .utf8))
                    .map { ConflictParser.parse($0).hunks.count } ?? 0
                entries.append(ConflictFile(path: path, resolved: resolved, conflicts: count))
            }
            conflictFiles = entries
            if let first = entries.first(where: { !$0.resolved }) {
                await loadConflictHunks(for: first.path)
            } else if let first = entries.first {
                await loadConflictHunks(for: first.path)
            }
        } catch {
            Self.logger.error("Failed to list unmerged paths: \(error.localizedDescription, privacy: .public)")
        }
    }

    func loadConflictHunks(for path: String) async {
        selectedConflictPath = path
        let absolute = repository.url.appendingPathComponent(path)
        do {
            let content = try String(contentsOf: absolute, encoding: .utf8)
            conflictHunks = ConflictParser.parse(content).hunks
            conflictPicks = [:]
        } catch {
            Self.logger.error("Failed to read \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            conflictHunks = []
        }
    }

    func setConflictPick(hunkId: UUID, pick: ConflictHunk.Pick) {
        conflictPicks[hunkId] = pick
    }

    /// One-shot conflict resolution: replaces the file content with one whole
    /// side and stages it. Used by the "Resolve using ours/theirs" context
    /// menu actions in `ConflictView`, where the user already knows they want
    /// the entire side without picking hunk-by-hunk.
    func resolveFile(at path: String, using side: ConflictHunk.Pick) async {
        do {
            switch side {
            case .ours:   try await cli.checkoutOurs(path: path)
            case .theirs: try await cli.checkoutTheirs(path: path)
            case .both:
                // No native git equivalent. Caller should use the per-hunk
                // resolver (the ConflictView UI) for `.both`.
                Self.logger.error("resolveFile(at:using: .both) is not supported — use the per-hunk resolver")
                return
            }
            try await cli.markResolved(path: path)
            await loadConflictState()
            await refreshStatus()
        } catch {
            Self.logger.error("Resolve \(path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            commitError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Writes the resolved version of `selectedConflictPath` to disk and stages
    /// it. Refreshes conflict state when done.
    func resolveSelectedFile() async {
        guard let path = selectedConflictPath else { return }
        let absolute = repository.url.appendingPathComponent(path)
        do {
            let original = try String(contentsOf: absolute, encoding: .utf8)
            let resolved = ConflictParser.apply(content: original, picks: conflictPicks, hunks: conflictHunks)
            try resolved.write(to: absolute, atomically: true, encoding: .utf8)
            try await cli.markResolved(path: path)
            await loadConflictState()
            await refreshStatus()
        } catch {
            Self.logger.error("Resolve failed: \(error.localizedDescription, privacy: .public)")
            commitError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func abortMerge() async {
        do {
            switch mergeState {
            case .merging:  try await cli.mergeAbort()
            case .rebasing: try await cli.rebaseAbort()
            // `.unmerged` (typically a stash apply conflict) has no native
            // abort — the user resolves manually or discards the affected
            // paths from Changes. Treat as no-op here.
            case .clean, .unmerged: return
            }
            await loadConflictState()
            await refreshStatus()
            await loadRefs(); await reloadLog()
        } catch {
            Self.logger.error("Abort failed: \(error.localizedDescription, privacy: .public)")
            commitError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Merges another branch into the current one. The result encodes whether
    /// the operation finished cleanly, paused on conflicts, or failed outright.
    enum IntegrationOutcome: Sendable, Equatable {
        case clean
        case conflicts
        case failed(String)
    }

    /// Convenience: merge `source` into the currently checked-out branch.
    func mergeBranch(_ source: GitRef) async -> IntegrationOutcome {
        await mergeBranch(source: source, into: nil)
    }

    /// Merges `source` into `target`. If `target` is nil or already the
    /// current branch, behaves like a direct `git merge`. Otherwise checks
    /// out `target` first so the merge lands on the right ref.
    func mergeBranch(source: GitRef, into target: GitRef?) async -> IntegrationOutcome {
        let sourceName = source.isLocalBranch ? source.name : source.displayName
        do {
            if let target, target.name != currentBranchName {
                guard target.isLocalBranch else {
                    return .failed("Can only merge into a local branch.")
                }
                try await cli.checkout(branch: target.name)
                await refreshAfterRefMutation(reloadLog: true)
            }
            try await cli.merge(branch: sourceName)
            await refreshAfterRefMutation(reloadLog: true)
            await loadConflictState()
            return .clean
        } catch {
            await loadConflictState()
            await refreshStatus()
            if mergeState.isInProgress {
                return .conflicts
            }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            commitError = message
            return .failed(message)
        }
    }

    func rebaseOnto(_ ref: GitRef) async -> IntegrationOutcome {
        let upstream = ref.isLocalBranch ? ref.name : ref.displayName
        do {
            try await cli.rebase(onto: upstream)
            await refreshAfterRefMutation(reloadLog: true)
            await loadConflictState()
            return .clean
        } catch {
            await loadConflictState()
            await refreshStatus()
            if mergeState.isInProgress {
                return .conflicts
            }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            commitError = message
            return .failed(message)
        }
    }

    func continueMerge() async {
        do {
            switch mergeState {
            case .merging:  try await cli.mergeContinue()
            case .rebasing: try await cli.rebaseContinue()
            // `.unmerged` has no continue command — once everything is staged
            // the user just commits. We refresh below to reflect the latest
            // resolution state regardless.
            case .clean, .unmerged: break
            }
            await loadConflictState()
            await refreshStatus()
            await loadRefs(); await reloadLog()
        } catch {
            Self.logger.error("Continue failed: \(error.localizedDescription, privacy: .public)")
            commitError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
