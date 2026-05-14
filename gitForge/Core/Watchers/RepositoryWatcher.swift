import Foundation
import os

/// Observes the working tree and `.git/` directory of a repository and emits
/// debounced refresh signals when something changes — typically because a CLI
/// command, another tool, or a colleague's pull updated the repo while the
/// app was in the background.
///
/// Picks the cheapest watch points possible:
/// - `.git/HEAD`        → checkout, branch creation, reset
/// - `.git/index`       → add / commit / restore
/// - `.git/refs`        → branch / tag mutations, fetch
/// - `.git/packed-refs` → after `git gc`
///
/// `onChange` is always called on the main actor.
@MainActor
final class RepositoryWatcher {
    private static let logger = Logger(subsystem: "com.warwarelabs.gitForge", category: "watcher")
    /// Long enough to absorb a chain of fs events from a single git op
    /// (a `commit` writes HEAD, refs, index in quick succession).
    private static let debounce: TimeInterval = 1.0
    /// Minimum gap between successful refreshes. Read-only git commands
    /// (status, log, rev-list…) still touch `.git/index` mtime via
    /// internal refresh logic — without a cooldown the refresh path
    /// triggers itself.
    private static let cooldown: TimeInterval = 1.5

    private var sources: [DispatchSourceFileSystemObject] = []
    private var workingTreeWatcher: WorkingTreeWatcher?
    private var pendingRefresh: Task<Void, Never>?
    private var isRefreshing = false
    private var lastRefresh: Date = .distantPast
    /// Set while the VM is running its own mutation (commit/stash/reset/…).
    /// Our own writes to `.git/HEAD`/`refs/*` would otherwise fire this
    /// watcher and trigger a parallel refresh while `refreshAfterIntegration`
    /// is mid-flight — doubling pressure on `.git/index.lock`.
    private var suspended = false
    private let onChange: @MainActor () async -> Void

    init(repository: URL, onChange: @escaping @MainActor () async -> Void) {
        self.onChange = onChange
        // Per-worktree gitdir holds HEAD and state files; the shared
        // commondir holds refs/ and packed-refs. In a regular repo they're
        // the same path. In a linked worktree (`.git` is a file), resolving
        // both correctly is the only way the watcher fires on ref/HEAD
        // changes — without this it sat permanently dark, opening file
        // descriptors against paths that don't exist on disk.
        let gitDir = GitCLI.resolveGitDirectory(in: repository)
            ?? repository.appendingPathComponent(".git")
        let commonDir = GitCLI.resolveGitCommonDirectory(in: repository)
            ?? gitDir
        watch(gitDir.appendingPathComponent("HEAD"))
        watch(commonDir.appendingPathComponent("packed-refs"))
        // refs/heads is enough to catch branch ops + fetch — watching
        // refs/ (parent) double-fires for every nested file. .git/index
        // is touched by read-only commands (status, log) so it's a known
        // false-positive source — leave it out and rely on the cooldown
        // check inside scheduleRefresh().
        watch(commonDir.appendingPathComponent("refs/heads"))
        watch(commonDir.appendingPathComponent("refs/remotes"))
        watch(commonDir.appendingPathComponent("refs/tags"))
        // Working-tree watcher catches IDE saves and external edits — the
        // .git/ sources above only fire on git ops, so without this the
        // Changes pane sat stale until the user ran a git command.
        workingTreeWatcher = WorkingTreeWatcher(root: repository) { [weak self] in
            self?.scheduleRefresh()
        }
    }

    deinit {
        sources.forEach { $0.cancel() }
        pendingRefresh?.cancel()
    }

    /// Manually trigger a refresh. `force` skips the cooldown — use it for
    /// user signals (window became key, app became active) where dropping
    /// the request would be visible as stale state.
    func poke(force: Bool = false) { scheduleRefresh(force: force) }

    /// Pause event handling while an in-app mutation is running so our own
    /// `.git/` writes don't bounce back as "external change". Caller pairs
    /// this with `resume()` in a defer.
    func suspend() {
        suspended = true
        pendingRefresh?.cancel()
    }

    /// Resume event handling. The VM is expected to have called
    /// `refreshAfterIntegration` already, so no implicit refresh here.
    func resume() {
        suspended = false
        lastRefresh = Date()
    }

    // MARK: private

    private func watch(_ url: URL) {
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { return }
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            Self.logger.error("watch(\(path, privacy: .public)) open failed")
            return
        }
        // No `.attrib` (would fire on every atime tick) and no `.extend`
        // (fires on append-mode index updates). Mutations git actually
        // makes show up as write/delete/rename on the file or its parent.
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scheduleRefresh()
        }
        source.setCancelHandler { close(fd) }
        source.activate()
        sources.append(source)
    }

    private func scheduleRefresh(force: Bool = false) {
        if suspended { return }
        // If we're mid-refresh, the in-flight task will already pick up the
        // newest state when it completes. No need to queue another.
        if isRefreshing { return }
        // Ignore events that arrive immediately after our own refresh —
        // those are git's own mtime jiggling, not real external work.
        // `force` overrides this for user-initiated signals (foreground,
        // window key) where staleness would be user-visible.
        if !force, Date().timeIntervalSince(lastRefresh) < Self.cooldown { return }

        pendingRefresh?.cancel()
        // Forced pokes also collapse the debounce — the user just told us
        // something changed, no point waiting another second to find out.
        let delay = force ? 0 : Self.debounce
        pendingRefresh = Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard let self, !Task.isCancelled else { return }
            self.isRefreshing = true
            await self.onChange()
            self.lastRefresh = Date()
            self.isRefreshing = false
        }
    }
}
