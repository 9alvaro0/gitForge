import Foundation
import os

extension RepositoryViewModel {
    func createBranch(name: String, startingAt: String? = nil, checkout: Bool) async -> Result<Void, Error> {
        do {
            try await cli.createBranch(name, startingAt: startingAt, checkout: checkout)
            await refreshAfterRefMutation(reloadLog: checkout)
            return .success(())
        } catch {
            Self.logger.error("Failed to create branch \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    func checkoutBranch(_ ref: GitRef) async -> Result<Void, Error> {
        let target = ref.isLocalBranch ? ref.name : ref.displayName
        do {
            try await cli.checkout(branch: target)
            await refreshAfterRefMutation(reloadLog: true)
            return .success(())
        } catch {
            Self.logger.error("Failed to checkout \(target, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    /// Checkout a raw SHA — yields a detached HEAD. Use `checkoutBranch(_:)`
    /// when a local branch already points at the commit so the user lands on
    /// a named branch instead.
    func checkoutCommit(_ sha: String) async -> Result<Void, Error> {
        do {
            try await cli.checkout(branch: sha)
            await refreshAfterRefMutation(reloadLog: true)
            return .success(())
        } catch {
            Self.logger.error("Failed to checkout commit \(sha, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    func deleteBranch(_ ref: GitRef, force: Bool = false) async -> Result<Void, Error> {
        do {
            try await cli.deleteBranch(ref.name, force: force)
            await refreshAfterRefMutation(reloadLog: false)
            return .success(())
        } catch {
            Self.logger.error("Failed to delete branch \(ref.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    func renameBranch(from oldName: String, to newName: String) async -> Result<Void, Error> {
        do {
            try await cli.renameBranch(from: oldName, to: newName)
            await refreshAfterRefMutation(reloadLog: false)
            return .success(())
        } catch {
            Self.logger.error("Failed to rename \(oldName, privacy: .public) to \(newName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    /// Move a non-current local branch tip to `sha` via `git branch -f`. The
    /// caller is responsible for routing HEAD moves through `reset(to:mode:)` —
    /// git refuses `branch -f` on the checked-out branch and we'd surface the
    /// raw stderr otherwise.
    /// Reloads the log because moving a tip changes which commits are
    /// reachable from `--all`, so the global graph topology can shift.
    func moveBranch(_ ref: GitRef, to sha: String) async -> Result<Void, Error> {
        do {
            try await cli.forceUpdateBranch(ref.name, to: sha)
            await refreshAfterRefMutation(reloadLog: true)
            return .success(())
        } catch {
            Self.logger.error("Failed to move \(ref.name, privacy: .public) to \(sha, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    func refreshAfterRefMutation(reloadLog: Bool) async {
        await loadRefs()
        await refreshStatus()
        if reloadLog {
            await self.reloadLog()
        }
    }
}
