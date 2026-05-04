import Foundation
import os

extension RepositoryViewModel {
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
