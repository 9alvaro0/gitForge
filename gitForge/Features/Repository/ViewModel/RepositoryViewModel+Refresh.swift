import Foundation

extension RepositoryViewModel {
    /// Reloads log, refs, and working copy from disk. Used by the manual
    /// "Refresh" command — git operations performed by gitForge already
    /// trigger their own targeted refreshes.
    func refresh() async {
        resetLog()
        async let logTask: Void = loadInitial()
        async let refsTask: Void = loadRefs()
        async let statusTask: Void = refreshStatus()
        _ = await logTask
        _ = await refsTask
        _ = await statusTask
    }
}
