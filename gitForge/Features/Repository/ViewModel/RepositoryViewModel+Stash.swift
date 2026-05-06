import Foundation
import os

extension RepositoryViewModel {
    func stashAll(message: String? = nil) async -> Result<Void, Error> {
        guard !status.isClean else {
            return .failure(StashError.nothingToStash)
        }
        do {
            try await cli.stashPush(message: message, includeUntracked: true)
            await loadRefs()
            await refreshStatus()
            return .success(())
        } catch {
            Self.logger.error("Stash push failed: \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    func applyStash(_ stash: Stash, drop: Bool) async {
        do {
            try await cli.stashApply(index: stash.index, drop: drop)
            await loadRefs()
            await refreshStatus()
        } catch {
            Self.logger.error("Stash apply failed: \(error.localizedDescription, privacy: .public)")
            commitError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func dropStash(_ stash: Stash) async {
        do {
            try await cli.stashDrop(index: stash.index)
            await loadRefs()
        } catch {
            Self.logger.error("Stash drop failed: \(error.localizedDescription, privacy: .public)")
            commitError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

enum StashError: LocalizedError {
    case nothingToStash

    var errorDescription: String? {
        switch self {
        case .nothingToStash: "No changes to stash"
        }
    }
}
