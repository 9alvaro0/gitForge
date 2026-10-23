import Foundation

extension RepositoryViewModel {
    /// Reloads log, refs, working copy, conflict state, and identity from
    /// disk. Used by the manual "Refresh" command — git operations performed
    /// by gitForge already trigger their own targeted refreshes.
    ///
    /// Mirrors `refreshFromExternalChange`'s coverage so the manual button
    /// can recover state when FSEvents misses a tick (system sleep, flake).
    func refresh() async {
        async let logTask: Void = history.reloadLog()
        async let refsTask: Void = loadRefs()
        async let statusTask: Void = workingCopy.refreshStatus()
        async let conflictTask: Void = loadConflictState()
        async let identityTask: Void = refreshIdentity()
        _ = await logTask
        _ = await refsTask
        _ = await statusTask
        _ = await conflictTask
        _ = await identityTask
        // The reload above runs alongside `loadRefs()`, so it may have built
        // its scope from the refs and stashes as they were before (a fetch or
        // a stash the watcher missed): reload once more if the new ones ask
        // for other remote branches or stashes.
        await reloadLogIfScopeMoved()
    }
}
