import Foundation
import os

extension RepositoryViewModel {
    func refreshStatus() async {
        isLoadingStatus = true
        defer { isLoadingStatus = false }
        do {
            status = try await cli.status()
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

    /// Stages a subset of hunks from the currently-selected unstaged file.
    func stageHunks(ids: Set<Int>) async {
        guard let file = selectedWorkingCopyFile, !file.isStaged else { return }
        guard let patch = PatchBuilder.makePatch(from: workingCopyFileDiff, hunkIds: ids) else { return }
        await runStageOperation {
            try await self.cli.applyPatch(patch, cached: true, reverse: false)
        }
        await loadWorkingCopyDiff(file: file)
    }

    /// Unstages a subset of hunks from the currently-selected staged file.
    func unstageHunks(ids: Set<Int>) async {
        guard let file = selectedWorkingCopyFile, file.isStaged else { return }
        guard let patch = PatchBuilder.makePatch(from: workingCopyFileDiff, hunkIds: ids) else { return }
        await runStageOperation {
            try await self.cli.applyPatch(patch, cached: true, reverse: true)
        }
        await loadWorkingCopyDiff(file: file)
    }

    func discardChanges(_ files: [WorkingCopyFile]) async {
        let tracked = files.filter { !$0.isUntracked }
        let untracked = files.filter(\.isUntracked)
        await runStageOperation {
            try await self.cli.discardChanges(paths: tracked.map(\.path))
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
            resetLog()
            await loadInitial()
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
