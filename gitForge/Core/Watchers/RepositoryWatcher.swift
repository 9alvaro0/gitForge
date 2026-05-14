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
    /// Coalescing window for a burst of fs events from one logical action
    /// (an editor "save" hits temp file + rename + chmod within ~50ms; a
    /// `git commit` writes HEAD, index, COMMIT_EDITMSG in quick succession).
    /// Short enough to feel live — `git status` is ~30ms on small repos so
    /// the user perceives the refresh as immediate — long enough that we
    /// don't fire three times per save.
    private static let debounce: TimeInterval = 0.3

    private var sources: [DispatchSourceFileSystemObject] = []
    private var workingTreeWatcher: WorkingTreeWatcher?
    private var pendingRefresh: Task<Void, Never>?
    private var isRefreshing = false
    /// Set when an event arrives while a refresh is already running. The
    /// running refresh observes this on completion and re-schedules so
    /// the new state is picked up — without it, an edit landing mid-flight
    /// is silently dropped.
    private var refreshDirty = false
    /// Set when an event arrives while `suspended == true`. `resume()` checks
    /// it and replays the missed signal as a normal scheduleRefresh — without
    /// this, an external edit that lands during one of our own mutations
    /// (commit, stash, discard…) vanished forever.
    private var pendingSuspendedEvent = false
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
        // is touched by read-only commands (status, log) so we deliberately
        // don't watch it — the WorkingTreeWatcher filters out `/.git/`
        // paths for the same reason, so there's no feedback loop to guard.
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

    /// Manually trigger a refresh. `force` skips the debounce — use it for
    /// user signals (window became key, app became active) where waiting
    /// 300ms would be visible as stale state.
    func poke(force: Bool = false) { scheduleRefresh(force: force) }

    /// Pause event handling while an in-app mutation is running so our own
    /// `.git/` writes don't bounce back as "external change". Caller pairs
    /// this with `resume()` in a defer.
    func suspend() {
        if Diagnostics.traceWatcher {
            Self.logger.debug("suspend()")
        }
        suspended = true
        pendingRefresh?.cancel()
    }

    /// Resume event handling. If any event landed while we were suspended,
    /// schedule a refresh now so the change isn't lost.
    func resume() {
        let hadPending = pendingSuspendedEvent
        suspended = false
        pendingSuspendedEvent = false
        if Diagnostics.traceWatcher {
            Self.logger.debug("resume() pending=\(hadPending, privacy: .public)")
        }
        if hadPending { scheduleRefresh() }
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
        if suspended {
            // Don't drop it: mark a single bit so `resume()` knows to fire
            // one refresh. Multiple events while suspended collapse into a
            // single replay — that's fine, the refresh reads fresh state
            // anyway.
            pendingSuspendedEvent = true
            if Diagnostics.traceWatcher {
                Self.logger.debug("scheduleRefresh deferred: suspended")
            }
            return
        }
        // Mid-refresh: mark dirty so the running task re-schedules itself
        // when it completes. Previously this branch just dropped the event,
        // so an edit landing during the refresh window was silently lost.
        if isRefreshing {
            refreshDirty = true
            if Diagnostics.traceWatcher {
                Self.logger.debug("scheduleRefresh deferred: in-flight refresh")
            }
            return
        }

        pendingRefresh?.cancel()
        let delay: TimeInterval = force ? 0 : Self.debounce
        if Diagnostics.traceWatcher {
            Self.logger.debug("scheduleRefresh fire force=\(force, privacy: .public) delay=\(delay, privacy: .public)s")
        }
        pendingRefresh = Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard let self, !Task.isCancelled else { return }
            self.isRefreshing = true
            self.refreshDirty = false
            if Diagnostics.traceWatcher {
                Self.logger.debug("onChange → start")
            }
            await self.onChange()
            self.isRefreshing = false
            if Diagnostics.traceWatcher {
                Self.logger.debug("onChange ← done dirty=\(self.refreshDirty, privacy: .public)")
            }
            // An event landed mid-refresh — schedule one more pass so the
            // new state lands without waiting for another external trigger.
            if self.refreshDirty {
                self.refreshDirty = false
                self.scheduleRefresh()
            }
        }
    }
}
