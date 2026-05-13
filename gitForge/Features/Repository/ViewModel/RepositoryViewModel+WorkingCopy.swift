import Foundation

extension RepositoryViewModel {
    /// Reads `git status` and applies the result. Gen-token gated because
    /// this is the highest-traffic refresh in the VM — overlapping calls
    /// would otherwise flicker the spinner off mid-flight (older `defer`
    /// firing while a fresher call is still awaiting) and leak stale
    /// `status` / selection-prune writes.
    func refreshStatus() async {
        statusGen &+= 1
        let gen = statusGen
        isLoadingStatus = true
        defer {
            if gen == statusGen {
                isLoadingStatus = false
                hasLoadedStatusOnce = true
            }
        }
        do {
            let snapshot = try await cli.status()
            guard gen == statusGen else { return }
            status = snapshot
            // Prune the diff-pane selection if the file no longer appears in
            // status (e.g. discarded, deleted) so the pane doesn't keep
            // showing a stale diff for a vanished file.
            if let selected = selectedWorkingCopyFile,
               !status.files.contains(where: { $0.path == selected.path }) {
                selectedWorkingCopyFile = nil
            }
        } catch {
            // Underlying `git status` failure is already logged by GitCLI.
        }
    }

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

    func runStageOperation(_ block: () async throws -> Void) async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            try await block()
            await refreshStatus()
        } catch {
            commitError = error.userMessage
            // Multi-step ops (discardChanges) may have committed half their work
            // to disk before throwing — refresh so the UI mirrors actual state.
            await refreshStatus()
        }
    }

    /// True when amending would rewrite a commit that's already on the upstream
    /// (and therefore visible to collaborators / would force-push on next push).
    var amendWouldRewritePublishedHistory: Bool {
        amendMode && upstream != nil && aheadCount == 0
    }

    func commit(confirmedAmendOfPublished: Bool = false) async -> Bool {
        guard !isMutating else { return false }
        commitError = nil
        let subject = commitSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subject.isEmpty else {
            commitError = "Commit subject cannot be empty"
            return false
        }
        guard amendMode || status.hasStagedChanges else {
            commitError = "Nothing staged to commit"
            return false
        }
        if amendWouldRewritePublishedHistory, !confirmedAmendOfPublished {
            commitError = "HEAD is already on the remote — amending rewrites public history. Confirm to force-push afterwards."
            return false
        }
        isMutating = true
        defer { isMutating = false }
        do {
            try await cli.commit(
                subject: subject,
                body: commitBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : commitBody,
                amend: amendMode
            )
            commitSubject = ""
            commitBody = ""
            amendMode = false
            // Single shared cluster — same helper used by +Operations /
            // +Pulls / +Stash / +Remote. Conflicts read is wasted after a
            // clean commit but harmless and keeps the refresh shape
            // uniform across every state-changing op.
            await refreshAfterIntegration()
            return true
        } catch {
            commitError = error.userMessage
            return false
        }
    }

    func prefillFromHead() async {
        do {
            let result = try await cli.run(["log", "-1", "HEAD", "--format=%B"])
            // A `false → true → false` toggle on `amendMode` clears
            // subject/body via the off-branch of the didSet. If this
            // prefill resumes after that, writing HEAD's message back
            // would look like the user re-armed amend. Bail when the
            // toggle has flipped off underneath us.
            guard amendMode else { return }
            let message = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if let firstNewline = message.firstIndex(of: "\n") {
                commitSubject = String(message[..<firstNewline])
                commitBody = String(message[message.index(after: firstNewline)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                commitSubject = message
                commitBody = ""
            }
        } catch {
            // Underlying `git log` failure is already logged by GitCLI.
        }
    }
}
