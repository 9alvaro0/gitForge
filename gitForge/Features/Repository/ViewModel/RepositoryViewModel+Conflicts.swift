import Foundation
import os

/// Conflict-resolution state on top of `RepositoryViewModel`.
extension RepositoryViewModel {
    /// Sides supported when resolving an entire conflicted file in one shot.
    /// `.both` only makes sense per-hunk so it stays in `ConflictHunk.Pick`,
    /// not here.
    enum WholeFilePick: Sendable, Equatable { case ours, theirs }

    /// Inspects worktree state, lists unmerged paths, and reads each one off
    /// the main thread to count conflict hunks. Preserves the user's current
    /// selection when the watcher fires mid-resolve so they don't get
    /// yanked back to the top of the list.
    func loadConflictState() async {
        mergeState = await cli.mergeState()
        guard mergeState.isInProgress else {
            conflictFiles = []
            conflictHunks = []
            conflictPicks = [:]
            selectedConflictPath = nil
            return
        }
        do {
            let paths = try await cli.unmergedPaths()
            let entries = await Self.scanConflictFiles(paths: paths,
                                                      repositoryURL: repository.url)
            conflictFiles = entries

            if let current = selectedConflictPath,
               entries.contains(where: { $0.path == current }) {
                return
            }
            let candidate = entries.first(where: { !$0.resolved }) ?? entries.first
            if let candidate {
                await loadConflictHunks(for: candidate.path)
            }
        } catch {
            // Underlying `git ls-files --unmerged` failure is logged by GitCLI.
        }
    }

    /// Reads each conflicted file off-MainActor and in parallel — a big merge
    /// can surface dozens of files and reading them serially on the main
    /// thread froze the UI.
    private nonisolated static func scanConflictFiles(paths: [String], repositoryURL: URL) async -> [ConflictFile] {
        await withTaskGroup(of: (Int, ConflictFile).self) { group in
            for (idx, path) in paths.enumerated() {
                group.addTask {
                    let abs = repositoryURL.appendingPathComponent(path)
                    let hunks = (try? String(contentsOf: abs, encoding: .utf8))
                        .map { ConflictParser.parse($0).hunks } ?? []
                    return (idx, ConflictFile(path: path,
                                              resolved: hunks.isEmpty,
                                              conflicts: hunks.count))
                }
            }
            var collected: [(Int, ConflictFile)] = []
            for await pair in group { collected.append(pair) }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// Loads conflict hunks for `path` and resets pending picks. Bumps
    /// `conflictHunksGen` so a slow load triggered for an older path can't
    /// stomp the freshly selected file.
    func loadConflictHunks(for path: String) async {
        conflictHunksGen &+= 1
        let gen = conflictHunksGen
        selectedConflictPath = path
        let absolute = repository.url.appendingPathComponent(path)
        do {
            let content = try await Self.readFile(at: absolute)
            guard gen == conflictHunksGen else { return }
            conflictHunks = ConflictParser.parse(content).hunks
            conflictPicks = [:]
        } catch {
            guard gen == conflictHunksGen else { return }
            Self.logger.error("Failed to read \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            conflictHunks = []
            conflictPicks = [:]
        }
    }

    private nonisolated static func readFile(at url: URL) async throws -> String {
        try await Task.detached { try String(contentsOf: url, encoding: .utf8) }.value
    }

    func setConflictPick(hunkId: UUID, pick: ConflictHunk.Pick) {
        conflictPicks[hunkId] = pick
    }

    /// Replaces the file content with one whole side and stages it. Used by
    /// the "Resolve using ours/theirs" context menu in `ConflictView`.
    func resolveFile(at path: String, using side: WholeFilePick) async {
        do {
            switch side {
            case .ours:   try await cli.checkoutOurs(path: path)
            case .theirs: try await cli.checkoutTheirs(path: path)
            }
            try await cli.markResolved(path: path)
            await loadConflictState()
            await refreshStatus()
        } catch {
            commitError = error.userMessage
        }
    }

    /// Applies the user's per-hunk picks to `selectedConflictPath` and stages
    /// it. Aborts before writing if the file's hunk count has shifted under
    /// us — that means an external edit landed and the picks no longer line
    /// up with the on-disk content; better to ask the user to reload than
    /// silently overwrite their changes.
    func resolveSelectedFile() async {
        guard let path = selectedConflictPath else { return }
        let absolute = repository.url.appendingPathComponent(path)
        do {
            let original = try await Self.readFile(at: absolute)
            let parsedNow = ConflictParser.parse(original).hunks
            guard parsedNow.count == conflictHunks.count else {
                commitError = "“\(path)” changed on disk — reload conflicts before resolving."
                return
            }
            let resolved = ConflictParser.apply(content: original, picks: conflictPicks, hunks: conflictHunks)
            try resolved.write(to: absolute, atomically: true, encoding: .utf8)
            try await cli.markResolved(path: path)
            await loadConflictState()
            await refreshStatus()
        } catch {
            commitError = error.userMessage
        }
    }

    /// Drops the in-progress integration and returns the worktree to clean.
    /// `.unmerged` (stash apply) and `.bisecting` don't go through here —
    /// stash has its own `abortStashApply`; bisect needs `git bisect reset`
    /// and is exposed separately.
    func abortMerge() async {
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
