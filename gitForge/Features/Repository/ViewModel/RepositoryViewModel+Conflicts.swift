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
            case .clean:    return
            }
            await loadConflictState()
            await refreshStatus()
            resetLog(); await loadInitial(); await loadRefs()
        } catch {
            Self.logger.error("Abort failed: \(error.localizedDescription, privacy: .public)")
            commitError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func continueMerge() async {
        do {
            switch mergeState {
            case .merging:  try await cli.mergeContinue()
            case .rebasing: try await cli.rebaseContinue()
            case .clean:    return
            }
            await loadConflictState()
            await refreshStatus()
            resetLog(); await loadInitial(); await loadRefs()
        } catch {
            Self.logger.error("Continue failed: \(error.localizedDescription, privacy: .public)")
            commitError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
