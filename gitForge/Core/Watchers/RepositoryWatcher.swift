import Foundation
import os

/// Observes the working tree and the git directory of a repository and emits
/// debounced refresh signals when something changes — typically because a CLI
/// command, another tool, or a colleague's pull updated the repo while the
/// app was in the background.
///
/// One `FileEventStream` covers the worktree plus the per-worktree gitdir and
/// the shared common dir (they live outside the worktree for linked
/// worktrees). `RepositoryEventFilter` keeps only meaningful paths: any
/// worktree file, and `HEAD` / refs (nested ones like `refs/heads/feature/x`
/// included) / packed-refs / in-progress markers inside the git dirs.
///
/// `onChange` is always called on the main actor.
@MainActor
final class RepositoryWatcher {
    private nonisolated static let logger = Logger(subsystem: "com.warwarelabs.gitForge", category: "watcher")
    /// Coalescing window for a burst of fs events from one logical action
    /// (an editor "save" hits temp file + rename + chmod within ~50ms; a
    /// `git commit` writes HEAD, index, COMMIT_EDITMSG in quick succession).
    /// Short enough to feel live — `git status` is ~30ms on small repos so
    /// the user perceives the refresh as immediate — long enough that we
    /// don't fire three times per save.
    private static let debounce: TimeInterval = 0.3

    private var stream: FileEventStream?
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
        // the same `<worktree>/.git`. In a linked worktree (`.git` is a file)
        // both live elsewhere and must be watched explicitly.
        let gitDir = GitCLI.resolveGitDirectory(in: repository)
            ?? repository.appendingPathComponent(".git")
        let commonDir = GitCLI.resolveGitCommonDirectory(in: repository) ?? gitDir
        let worktreePath = repository.canonicalFileSystemPath
        let gitPaths = Array(Set([gitDir.canonicalFileSystemPath, commonDir.canonicalFileSystemPath]))
        let filter = RepositoryEventFilter(worktree: worktreePath, gitDirectories: gitPaths)
        // Only directories outside the worktree need their own root.
        let roots = [worktreePath] + gitPaths.filter { !$0.hasPrefix(worktreePath + "/") }
        stream = FileEventStream(paths: roots) { [weak self] batch in
            let relevant = filter.isRelevant(batch)
            if Diagnostics.traceWatcher {
                Self.logger.debug("event count=\(batch.paths.count, privacy: .public) relevant=\(relevant, privacy: .public) first=\(batch.paths.first ?? "-", privacy: .public)")
            }
            guard relevant else { return }
            Task { @MainActor [weak self] in self?.scheduleRefresh() }
        }
    }

    deinit {
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
