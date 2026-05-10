import Foundation

extension RepositoryViewModel {
    func createBranch(name: String, startingAt: String? = nil, checkout: Bool) async -> Result<Void, Error> {
        guard BranchValidator.isValidName(name) else {
            return .failure(BranchOpError.invalidName(name))
        }
        do {
            try await cli.createBranch(name, startingAt: startingAt, checkout: checkout)
            await refreshAfterRefMutation(reloadLog: checkout)
            return .success(())
        } catch {
            await loadRefs()
            return .failure(error)
        }
    }

    func checkoutBranch(_ ref: GitRef) async -> Result<Void, Error> {
        // For a remote ref like `origin/main` we hand git the bare `main` so
        // it DWIMs into a local tracking branch — matches GitKraken/Sourcetree
        // UX where clicking a remote branch lands you on a local copy.
        let target = ref.isLocalBranch ? ref.name : ref.displayName
        do {
            try await cli.checkout(branch: target)
            await refreshAfterRefMutation(reloadLog: true)
            return .success(())
        } catch {
            await loadRefs()
            return .failure(error)
        }
    }

    /// Checkout a raw SHA — yields a detached HEAD. Use `checkoutBranch(_:)`
    /// when a local branch already points at the commit.
    func checkoutCommit(_ sha: String) async -> Result<Void, Error> {
        do {
            try await cli.checkout(branch: sha)
            await refreshAfterRefMutation(reloadLog: true)
            return .success(())
        } catch {
            await loadRefs()
            return .failure(error)
        }
    }

    func deleteBranch(_ ref: GitRef, force: Bool = false) async -> Result<Void, Error> {
        do {
            try await cli.deleteBranch(ref.name, force: force)
            await refreshAfterRefMutation(reloadLog: false)
            return .success(())
        } catch {
            await loadRefs()
            return .failure(error)
        }
    }

    func renameBranch(from oldName: String, to newName: String) async -> Result<Void, Error> {
        guard BranchValidator.isValidName(newName) else {
            return .failure(BranchOpError.invalidName(newName))
        }
        do {
            try await cli.renameBranch(from: oldName, to: newName)
            await refreshAfterRefMutation(reloadLog: false)
            return .success(())
        } catch {
            await loadRefs()
            return .failure(error)
        }
    }

    /// Move a non-current local branch tip to `sha` via `git branch -f`.
    /// Reloads the log because moving a tip changes graph topology. Route
    /// HEAD moves through `reset(to:mode:)` — git refuses `branch -f` on the
    /// checked-out branch.
    func moveBranch(_ ref: GitRef, to sha: String) async -> Result<Void, Error> {
        guard ref.isLocalBranch else {
            return .failure(BranchOpError.notALocalBranch)
        }
        if ref.name == currentBranchName {
            return .failure(BranchOpError.cannotMoveCurrentBranch)
        }
        do {
            try await cli.forceUpdateBranch(ref.name, to: sha)
            await refreshAfterRefMutation(reloadLog: true)
            return .success(())
        } catch {
            await loadRefs()
            return .failure(error)
        }
    }

    /// `loadRefs` and `refreshStatus` are independent (status doesn't read
    /// refs), so we run them in parallel. `reloadLog` depends on the freshly
    /// loaded `unmergedLocalBranchRefs` and `stashes` and stays sequential.
    func refreshAfterRefMutation(reloadLog: Bool) async {
        async let refsTask: Void = loadRefs()
        async let statusTask: Void = refreshStatus()
        _ = await (refsTask, statusTask)
        if reloadLog { await self.reloadLog() }
    }
}

enum BranchOpError: LocalizedError {
    case invalidName(String)
    case notALocalBranch
    case cannotMoveCurrentBranch

    var errorDescription: String? {
        switch self {
        case .invalidName(let name):
            "Invalid branch name “\(name)”."
        case .notALocalBranch:
            "Only local branches can be moved."
        case .cannotMoveCurrentBranch:
            "Cannot move the currently checked-out branch — use Reset instead."
        }
    }
}
