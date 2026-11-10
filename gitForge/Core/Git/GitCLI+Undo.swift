import Foundation

/// Recording and applying `UndoOperation`s. Every capture runs just before
/// (or right after) the operation it undoes; `performUndo` checks the
/// repository is still where that operation left it and throws
/// `UndoRefusal` otherwise, so an undo never lands on top of a later change.
extension GitCLI {
    // MARK: Capture

    /// The commit `ref` points at, or `nil` when it doesn't exist.
    func resolvedSha(_ ref: String) async -> String? {
        guard let result = try? await run(["rev-parse", "--verify", "--quiet", Self.endOfOptions, "\(ref)^{commit}"])
        else { return nil }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The index and the tracked files on disk as trees, written to the
    /// object database without touching either (nothing is staged or
    /// stashed). `nil` when both match HEAD. Throws when git can't write
    /// them, e.g. with unmerged paths.
    ///
    /// Not `git stash create`: its worktree tree keeps a staged new file
    /// that was then deleted on disk. Here the worktree goes through
    /// `add -u` into a copy of the index, which records every change to a
    /// tracked path, deletions included.
    func snapshotWorkingTree() async throws -> WorkingTreeSnapshot? {
        let index = Self.trimmed(try await run(["write-tree"]).stdout)
        let indexPath = Self.trimmed(try await run(["rev-parse", "--path-format=absolute", "--git-path", "index"]).stdout)
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitForge-snapshot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        if FileManager.default.fileExists(atPath: indexPath) {
            try FileManager.default.copyItem(at: URL(fileURLWithPath: indexPath), to: scratch)
        }
        let environment = ["GIT_INDEX_FILE": scratch.path(percentEncoded: false)]
        try await run(["add", "-u", "--", ":/"], environment: environment)
        let worktree = Self.trimmed(try await run(["write-tree"], environment: environment).stdout)
        // `nil` while HEAD is unborn: anything written is a change.
        let headTree = (try? await run(["rev-parse", "--verify", "--quiet", "HEAD^{tree}"]))
            .map { Self.trimmed($0.stdout) }
        guard index != headTree || worktree != headTree else { return nil }
        return WorkingTreeSnapshot(index: index, worktree: worktree)
    }

    nonisolated static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// What a reset needs to be undone, read just before it runs. `nil`
    /// when HEAD is unborn or the tree can't be snapshotted.
    func captureReset(mode: ResetMode) async -> ResetCapture? {
        guard let head = await headSha() else { return nil }
        let snapshot: WorkingTreeSnapshot?
        do { snapshot = try await snapshotWorkingTree() } catch { return nil }
        return ResetCapture(branch: await currentBranchName(), mode: mode, previousSha: head, snapshot: snapshot)
    }

    nonisolated struct ResetCapture: Sendable, Equatable {
        let branch: String?
        let mode: ResetMode
        let previousSha: String
        let snapshot: WorkingTreeSnapshot?
    }

    /// The undo for a reset that has just run, or `nil` when it changed
    /// nothing worth undoing (same commit, and nothing unstaged or lost).
    func resetUndo(after capture: ResetCapture) async -> UndoOperation? {
        guard let result = await headSha() else { return nil }
        let lostWork = capture.mode != .soft && capture.snapshot != nil
        guard result != capture.previousSha || lostWork else { return nil }
        return .reset(.init(branch: capture.branch, mode: capture.mode, previousSha: capture.previousSha,
                            resultSha: result, snapshot: capture.snapshot))
    }

    /// Tip and `branch.<name>.*` config of a local branch about to be
    /// deleted; `nil` when it doesn't exist.
    func captureBranchDeletion(_ name: String) async -> UndoOperation? {
        guard let sha = await resolvedSha("refs/heads/\(name)") else { return nil }
        return .deleteBranch(name: name, sha: sha, config: await branchConfig(name))
    }

    /// `branch.<name>.*` entries in the repository's own config, in order.
    func branchConfig(_ name: String) async -> [UndoOperation.ConfigEntry] {
        let pattern = "^branch\\.\(Self.regexEscaped(name))\\."
        // Exit code 1 means no entries.
        guard let result = try? await run(["config", "--local", "-z", "--get-regexp", pattern]) else { return [] }
        return Self.parseConfigEntries(result.stdout)
    }

    /// `git config -z` output: `key\nvalue\0` per entry (a key with no
    /// value has no newline).
    nonisolated static func parseConfigEntries(_ output: String) -> [UndoOperation.ConfigEntry] {
        splitNul(output).map { entry in
            guard let newline = entry.firstIndex(of: "\n") else {
                return UndoOperation.ConfigEntry(key: entry, value: "")
            }
            return UndoOperation.ConfigEntry(key: String(entry[..<newline]),
                                             value: String(entry[entry.index(after: newline)...]))
        }
    }

    nonisolated static func regexEscaped(_ text: String) -> String {
        let special: Set<Character> = [".", "^", "$", "*", "+", "?", "(", ")", "[", "]", "{", "}", "|", "\\", "/"]
        return String(text.flatMap { special.contains($0) ? ["\\", $0] : [$0] })
    }

    /// Index entries and worktree diff of `paths`: equal before and after
    /// means nobody touched them in between.
    func worktreeFingerprint(paths: [String]) async throws -> String {
        guard !paths.isEmpty else { return "" }
        let index = try await run(["ls-files", "-s", "-z", "--"] + paths)
        let diff = try await run(["diff", "--no-ext-diff", "--no-color", "--binary"] + Self.diffOutputFlags + ["--"] + paths)
        return index.stdout + "\0" + diff.stdout
    }

    /// The undo for discarding tracked `paths`, from a snapshot taken just
    /// before. `nil` when there's nothing to restore.
    func discardUndo(snapshot: WorkingTreeSnapshot?, paths: [String]) async -> UndoOperation? {
        guard let snapshot, !paths.isEmpty,
              let fingerprint = try? await worktreeFingerprint(paths: paths) else { return nil }
        return .discard(.init(snapshot: snapshot.worktree, paths: paths, fingerprint: fingerprint))
    }

    // MARK: Apply

    func performUndo(_ operation: UndoOperation) async throws {
        switch operation {
        case .reset(let reset):
            try await undoReset(reset)
        case .moveBranch(let name, let movedTo, let previous):
            try await undoMove(name: name, movedTo: movedTo, previous: previous)
        case .deleteBranch(let name, let sha, let config):
            try await undoDelete(name: name, sha: sha, config: config)
        case .dropStash(let sha, let message):
            try await undoDrop(sha: sha, message: message)
        case .discard(let restore):
            try await undoDiscard(restore)
        case .forcePush(let remote, let branch, let pushed, let previous):
            try await undoForcePush(remote: remote, branch: branch, pushed: pushed, previous: previous)
        }
    }

    private func undoReset(_ reset: UndoOperation.HeadReset) async throws {
        let target = reset.branch ?? "HEAD"
        guard await currentBranchName() == reset.branch,
              await headSha() == reset.resultSha else { throw UndoRefusal.headMoved(target) }
        guard Self.isObjectId(reset.previousSha), await resolvedSha(reset.previousSha) != nil else {
            throw UndoRefusal.objectMissing
        }
        // A full hex SHA can't be read as an option. Not `--end-of-options`:
        // `git reset` before 2.4x rejects it there.
        switch reset.mode {
        case .soft:
            // The index and worktree were left alone: moving HEAD back is the inverse.
            try await run(["reset", "-q", "--soft", reset.previousSha])
        case .mixed:
            // Only the index changed; it must still be what the reset left.
            guard try await indexMatchesHead() else { throw UndoRefusal.changesSinceReset }
            try await run(["reset", "-q", "--mixed", reset.previousSha])
            if let snapshot = reset.snapshot {
                try await run(["read-tree", Self.endOfOptions, snapshot.index])
            }
        case .hard:
            guard try await trackedTreeIsClean() else { throw UndoRefusal.changesSinceReset }
            try await run(["reset", "-q", "--hard", reset.previousSha])
            if let snapshot = reset.snapshot {
                // Files on disk (and the index) from the worktree tree, then
                // the index as it was: staged and unstaged changes come back apart.
                try await run(["read-tree", "-u", "--reset", Self.endOfOptions, snapshot.worktree])
                try await run(["read-tree", Self.endOfOptions, snapshot.index])
            }
        }
    }

    nonisolated static func isObjectId(_ text: String) -> Bool {
        (text.count == 40 || text.count == 64) && text.allSatisfy(\.isHexDigit)
    }

    private func undoMove(name: String, movedTo: String, previous: String) async throws {
        let ref = "refs/heads/\(name)"
        guard await resolvedSha(ref) == movedTo else { throw UndoRefusal.branchMoved(name) }
        // `update-ref` on the checked-out branch would leave the index and
        // worktree behind: that's a reset, not a move.
        guard await currentBranchName() != name else { throw UndoRefusal.branchCheckedOut(name) }
        guard await resolvedSha(previous) != nil else { throw UndoRefusal.objectMissing }
        do {
            // Compare-and-swap: refused if the branch moved since the check.
            try await run(["update-ref", "-m", "gitForge: undo move", ref, previous, movedTo])
        } catch {
            throw UndoRefusal.branchMoved(name)
        }
    }

    private func undoDelete(name: String, sha: String, config: [UndoOperation.ConfigEntry]) async throws {
        let ref = "refs/heads/\(name)"
        guard await resolvedSha(ref) == nil else { throw UndoRefusal.branchExists(name) }
        guard await resolvedSha(sha) != nil else { throw UndoRefusal.objectMissing }
        do {
            // An empty old value: only if the ref still doesn't exist.
            try await run(["update-ref", "-m", "gitForge: undo delete", ref, sha, ""])
        } catch {
            throw UndoRefusal.branchExists(name)
        }
        // git dropped `branch.<name>.*` with the branch; anything there now
        // was set since, so ours only adds to it.
        for entry in config {
            try await run(["config", "--local", "--add", Self.endOfOptions, entry.key, entry.value])
        }
    }

    private func undoDrop(sha: String, message: String) async throws {
        guard !(try await stashes().contains(where: { $0.sha == sha })) else { throw UndoRefusal.stashAlreadyListed }
        guard await resolvedSha(sha) != nil else { throw UndoRefusal.objectMissing }
        try await run(["stash", "store", "-q", "-m", message, sha])
    }

    private func undoDiscard(_ restore: UndoOperation.WorktreeRestore) async throws {
        guard try await worktreeFingerprint(paths: restore.paths) == restore.fingerprint else {
            throw UndoRefusal.filesChanged
        }
        guard Self.isObjectId(restore.snapshot),
              (try? await run(["cat-file", "-e", "\(restore.snapshot)^{tree}"])) != nil else {
            throw UndoRefusal.objectMissing
        }
        // Worktree only: the index never changed. A path the snapshot lacks
        // (deleted on disk before the discard) is deleted again.
        try await runInBatches(["restore", "--source=\(restore.snapshot)", "--worktree", "--"],
                                   paths: restore.paths)
    }

    private func undoForcePush(remote: String, branch: String, pushed: String, previous: String) async throws {
        guard await resolvedSha(previous) != nil else { throw UndoRefusal.objectMissing }
        let ref = "refs/heads/\(branch)"
        do {
            try await runNetwork(["push", "--force-with-lease=\(ref):\(pushed)", Self.endOfOptions,
                                  remote, "\(previous):\(ref)"], remote: remote)
        } catch let error as GitError {
            if case .commandFailed(_, _, let stderr) = error, stderr.contains("stale info") {
                throw UndoRefusal.remoteMoved("\(remote)/\(branch)")
            }
            throw error
        }
    }

    // MARK: Checks

    /// `git diff --cached --quiet`: the index has nothing staged.
    private func indexMatchesHead() async throws -> Bool {
        try await quietDiff(["diff", "--cached", "--quiet"])
    }

    /// No staged or unstaged changes to tracked files.
    private func trackedTreeIsClean() async throws -> Bool {
        let staged = try await quietDiff(["diff", "--cached", "--quiet"])
        let unstaged = try await quietDiff(["diff", "--quiet"])
        return staged && unstaged
    }

    /// Exit 0: no differences; exit 1: some; anything else is an error.
    private func quietDiff(_ args: [String]) async throws -> Bool {
        do {
            try await run(args)
            return true
        } catch GitError.commandFailed(_, let exitCode, _) where exitCode == 1 {
            return false
        }
    }
}
