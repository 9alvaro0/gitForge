import Foundation
import os

extension RepositoryViewModel {
    func refreshStatus() async {
        isLoadingStatus = true
        defer {
            isLoadingStatus = false
            hasLoadedStatusOnce = true
        }
        do {
            status = try await cli.status()
            // Prune the diff-pane selection if the file no longer appears in
            // status (e.g. discarded, deleted) so the pane doesn't keep
            // showing a stale diff for a vanished file.
            if let selected = selectedWorkingCopyFile,
               !status.files.contains(where: { $0.path == selected.path }) {
                selectedWorkingCopyFile = nil
            }
        } catch {
            Self.logger.error("Failed to load status: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stage(_ files: [WorkingCopyFile]) async {
        await runStageOperation { try await self.cli.stage(paths: files.map(\.path)) }
    }

    func unstage(_ files: [WorkingCopyFile]) async {
        await runStageOperation { try await self.cli.unstage(paths: files.map(\.path)) }
    }

    func discardChanges(_ files: [WorkingCopyFile]) async {
        // `git restore --` refuses unmerged paths, so they need a separate
        // command (`git checkout HEAD --`) that overwrites both index and
        // worktree from HEAD. Untracked files are filesystem-only deletes.
        let unmerged = files.filter(\.isUnmerged)
        let untracked = files.filter { $0.isUntracked && !$0.isUnmerged }
        let tracked = files.filter { !$0.isUntracked && !$0.isUnmerged }
        await runStageOperation {
            try await self.cli.discardChanges(paths: tracked.map(\.path))
            try await self.cli.discardUnmerged(paths: unmerged.map(\.path))
            try await self.cli.deleteUntracked(paths: untracked.map(\.path))
        }
    }

    func runStageOperation(_ block: () async throws -> Void) async {
        do {
            try await block()
            await refreshStatus()
        } catch {
            Self.logger.error("Stage operation failed: \(error.localizedDescription, privacy: .public)")
            commitError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func commit() async -> Bool {
        let subject = commitSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subject.isEmpty else {
            commitError = "Commit subject cannot be empty"
            return false
        }
        guard amendMode || status.hasStagedChanges else {
            commitError = "Nothing staged to commit"
            return false
        }
        do {
            try await cli.commit(
                subject: subject,
                body: commitBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : commitBody,
                amend: amendMode
            )
            commitSubject = ""
            commitBody = ""
            amendMode = false
            commitError = nil
            await refreshStatus()
            await loadRefs()
            await reloadLog()
            return true
        } catch {
            Self.logger.error("Commit failed: \(error.localizedDescription, privacy: .public)")
            commitError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func prefillFromHead() async {
        do {
            let result = try await cli.run(["log", "-1", "HEAD", "--format=%B"])
            let message = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if let firstNewline = message.firstIndex(of: "\n") {
                commitSubject = String(message[..<firstNewline])
                commitBody = String(message[message.index(after: firstNewline)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                commitSubject = message
                commitBody = ""
            }
        } catch {
            Self.logger.error("Failed to read HEAD message: \(error.localizedDescription, privacy: .public)")
        }
    }
}
