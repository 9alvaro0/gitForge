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
        await runStageOperation {
            try await self.cli.discardChanges(paths: tracked.map(\.path) + renameRestores)
            try await self.cli.discardUnmerged(paths: unmerged.map(\.path))
            try await self.cli.deleteUntracked(paths: untracked.map(\.path) + renameDeletes)
        }
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

    func runStageOperation(_ block: () async throws -> Void) async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            try await block()
            await workingCopy.refreshStatus()
        } catch {
            commitError = error.userMessage
            // Multi-step ops (discardChanges) may have committed half their work
            // to disk before throwing — refresh so the UI mirrors actual state.
            await workingCopy.refreshStatus()
        }
    }

    /// True when amending would rewrite a commit that's already on the upstream
    /// (and therefore visible to collaborators / would force-push on next push).
    var amendWouldRewritePublishedHistory: Bool {
        workingCopy.amendMode && upstream != nil && aheadCount == 0
    }

    func commit(confirmedAmendOfPublished: Bool = false) async -> Bool {
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
                signOff: workingCopy.signOff
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
            commitError = error.userMessage
            return false
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
        /// Worktree change → gone. Not undoable.
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
        await runStageOperation {
            try await self.cli.apply(patch: patch, cached: action != .discard, reverse: reverse)
        }
        // The file can stay in the same state (still modified on both sides),
        // in which case the status refresh didn't reload its diff.
        await workingCopy.reloadSelectedDiff()
    }
}
