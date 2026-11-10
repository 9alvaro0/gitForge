import Foundation

extension RepositoryViewModel {
    func stage(_ files: [WorkingCopyFile]) async {
        // Use `allPaths` so renames (staged or unstaged-detected) carry both
        // the new and old paths into a single `git add` invocation. Without
        // the old path, git stages the new file as an "add" and leaves the
        // delete unstaged, breaking the rename detection in the index.
        await runStageOperation { try await self.cli.stage(paths: files.flatMap(\.allPaths)) }
    }

    func unstage(_ files: [WorkingCopyFile]) async {
        await runStageOperation { try await self.cli.unstage(paths: files.flatMap(\.allPaths)) }
    }

    /// Offers its undo for the tracked changes (from a snapshot taken just
    /// before); untracked files go to the Trash, and the toast says so.
    func discardChanges(_ files: [WorkingCopyFile]) async {
        // `git restore --` refuses unmerged paths, so they need a separate
        // command (`git checkout HEAD --`) that overwrites both index and
        // worktree from HEAD. Untracked files are filesystem-only deletes.
        // Detected unstaged renames need both: restore the old path from
        // HEAD (it's been deleted on disk) and remove the new path.
        let unmerged = files.filter(\.isUnmerged)
        let detectedRenames = files.filter { $0.unstagedStatus == .renamed && !$0.isStaged }
        let untracked = files.filter { $0.isUntracked && !$0.isUnmerged && $0.unstagedStatus != .renamed }
        let tracked = files.filter {
            !$0.isUntracked && !$0.isUnmerged && $0.unstagedStatus != .renamed
        }
        let renameRestores = detectedRenames.compactMap(\.originalPath)
        let renameDeletes = detectedRenames.map(\.path)
        let restored = tracked.map(\.path) + renameRestores
        var removal = UntrackedRemoval()
        let done = await runStageOperation {
            // Before anything goes. git can't snapshot unmerged paths: the
            // discard then runs without an undo.
            var snapshot: WorkingTreeSnapshot?
            if !restored.isEmpty { snapshot = try? await self.cli.snapshotWorkingTree() }
            try await self.cli.discardChanges(paths: restored)
            try await self.cli.discardUnmerged(paths: unmerged.map(\.path))
            try await self.cli.deleteUntracked(paths: renameDeletes)
            removal = try await self.cli.deleteUntracked(paths: untracked.map(\.path))
            if unmerged.isEmpty {
                self.undo.record(await self.cli.discardUndo(snapshot: snapshot, paths: restored))
            }
        }
        guard done else { return }
        operationSuccess = .discard(files: tracked.count + detectedRenames.count + unmerged.count,
                                    removal: removal, undoID: undo.pending?.id)
    }

    // MARK: Bulk selection

    /// Stage every selected file that's currently unstaged. Clears their
    /// selection on success — they're moving sections, so keeping the tick
    /// would re-pre-select them in the Staged column.
    func stageSelected() async {
        let toStage = workingCopy.selectedUnstagedFiles
        guard !toStage.isEmpty else { return }
        await stage(toStage)
        workingCopy.deselect(toStage)
    }

    /// Unstage every selected file that's currently staged.
    func unstageSelected() async {
        let toUnstage = workingCopy.selectedStagedFiles
        guard !toUnstage.isEmpty else { return }
        await unstage(toUnstage)
        workingCopy.deselect(toUnstage)
    }

    /// Whether `block` ran and succeeded.
    @discardableResult
    func runStageOperation(_ block: () async throws -> Void) async -> Bool {
        guard !isMutating else { return false }
        isMutating = true
        defer { isMutating = false }
        do {
            try await block()
            await workingCopy.refreshStatus()
            return true
        } catch {
            commitError = error.userMessage
            // Multi-step ops (discardChanges) may have committed half their work
            // to disk before throwing — refresh so the UI mirrors actual state.
            await workingCopy.refreshStatus()
            return false
        }
    }

    /// True when amending would rewrite a commit that's already on the upstream
    /// (and therefore visible to collaborators / would force-push on next push).
    var amendWouldRewritePublishedHistory: Bool {
        workingCopy.amendMode && upstream != nil && aheadCount == 0
    }

    /// `pushAfterwards` only matters if a hook stops the commit: the hook
    /// sheet's Retry then pushes too, like "Commit & push" would have.
    /// `skipHooks` commits with `--no-verify`. The subject and body are only
    /// cleared on success, so a failed commit keeps the message.
    func commit(confirmedAmendOfPublished: Bool = false, pushAfterwards: Bool = false,
                skipHooks: Bool = false) async -> Bool {
        guard !isMutating else { return false }
        commitError = nil
        let subject = workingCopy.commitSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subject.isEmpty else {
            commitError = String(localized: "Commit subject cannot be empty")
            return false
        }
        guard workingCopy.amendMode || workingCopy.status.hasStagedChanges else {
            commitError = String(localized: "Nothing staged to commit")
            return false
        }
        if amendWouldRewritePublishedHistory, !confirmedAmendOfPublished {
            commitError = String(localized: "HEAD is already on the remote — amending rewrites public history. Confirm to force-push afterwards.")
            return false
        }
        let body = workingCopy.commitBody
        let amend = workingCopy.amendMode
        isMutating = true
        defer { isMutating = false }
        do {
            try await cli.commit(
                subject: subject,
                body: body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : body,
                amend: amend,
                signOff: workingCopy.signOff,
                skipHooks: skipHooks
            )
            workingCopy.resetComposer()
            // Single shared cluster — same helper used by +Operations /
            // +Pulls / +Stash / +Remote. Conflicts read is wasted after a
            // clean commit but harmless and keeps the refresh shape
            // uniform across every state-changing op.
            await refreshAfterIntegration()
            let shortSha = await cli.headSha().map { String($0.prefix(7)) }
            operationSuccess = .commit(shortSha: shortSha, subject: subject, amend: amend)
            return true
        } catch {
            let operation = HookFailure.Operation.commit(pushAfterwards: pushAfterwards,
                                                         confirmedAmendOfPublished: confirmedAmendOfPublished)
            if let failure = await detectHookFailure(in: error, operation: operation) {
                hookFailure = failure
                commitError = failure.summary
            } else {
                commitError = error.userMessage
            }
            return false
        }
    }

    /// The hook failure behind `error`, if a commit hook is installed and the
    /// failure isn't one git reports itself.
    func detectHookFailure(in error: Error, operation: HookFailure.Operation) async -> HookFailure? {
        guard case GitError.commandFailed(_, _, let stderr) = error else { return nil }
        let installed = await cli.installedHooks(HookFailure.commitHooks)
        return HookFailure(stderr: stderr, operation: operation, installedHooks: installed)
    }

    /// The hook sheet's Retry (`skipHooks: false`) and "Commit without hooks"
    /// (`skipHooks: true`, commits only). Runs the same operation again; a
    /// new failure raises a new sheet.
    func retry(_ failure: HookFailure, skipHooks: Bool = false) async {
        if hookFailure?.id == failure.id { hookFailure = nil }
        switch failure.operation {
        case .commit(let pushAfterwards, let confirmed):
            let committed = await commit(confirmedAmendOfPublished: confirmed,
                                         pushAfterwards: pushAfterwards,
                                         skipHooks: skipHooks)
            if committed, pushAfterwards { _ = await push() }
        case .continueIntegration:
            await continueMerge()
        }
    }
}

// MARK: Hunks

extension RepositoryViewModel {
    enum HunkAction: Sendable, Equatable {
        /// Worktree change → index.
        case stage
        /// Index change → back to the worktree only.
        case unstage
        /// Worktree change → gone. Offers its undo.
        case discard
    }

    /// Whether the pane may offer hunk actions for `file`. They need a plain
    /// text diff read from git with whitespace intact: untracked, unmerged
    /// and renamed files go whole-file, and a `-w` diff's hunks don't match
    /// the file.
    func canApplyHunks(to file: WorkingCopyFile) -> Bool {
        !file.isUntracked && !file.isUnmerged && file.originalPath == nil
            && !GitPreferences.diffIgnoreWhitespace
    }

    /// Stages, unstages or discards `hunk` of `file` — or only the lines in
    /// `lineIds` — then refreshes status and the open diff. Failures land in
    /// `commitError`, like the whole-file actions.
    func apply(_ action: HunkAction, hunk: DiffHunk, lineIds: Set<Int>? = nil, in file: WorkingCopyFile) async {
        let reverse = action != .stage
        guard canApplyHunks(to: file),
              let patch = HunkPatch.make(path: file.path, hunk: hunk, selectedLineIds: lineIds, reverse: reverse)
        else { return }
        let discard = action == .discard
        let done = await runStageOperation {
            var snapshot: WorkingTreeSnapshot?
            if discard { snapshot = try? await self.cli.snapshotWorkingTree() }
            try await self.cli.apply(patch: patch, cached: !discard, reverse: reverse)
            if discard {
                self.undo.record(await self.cli.discardUndo(snapshot: snapshot, paths: [file.path]))
            }
        }
        // The file can stay in the same state (still modified on both sides),
        // in which case the status refresh didn't reload its diff.
        await workingCopy.reloadSelectedDiff()
        if done, discard {
            operationSuccess = .discardHunk(lines: lineIds != nil, undoID: undo.pending?.id)
        }
    }
}
