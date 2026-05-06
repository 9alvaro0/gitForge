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
    private var pendingRefresh: Task<Void, Never>?
    private var isRefreshing = false
    private var lastRefresh: Date = .distantPast
    private let onChange: @MainActor () async -> Void

    init(repository: URL, onChange: @escaping @MainActor () async -> Void) {
        self.onChange = onChange
        let gitDir = repository.appendingPathComponent(".git")
        watch(gitDir.appendingPathComponent("HEAD"))
        watch(gitDir.appendingPathComponent("packed-refs"))
        // .git/refs/heads is enough to catch branch ops + fetch — watching
        // .git/refs (parent) double-fires for every nested file. .git/index
        // is touched by read-only commands (status, log) so it's a known
        // false-positive source — leave it out and rely on the cooldown
        // check inside scheduleRefresh().
        watch(gitDir.appendingPathComponent("refs/heads"))
        watch(gitDir.appendingPathComponent("refs/remotes"))
        watch(gitDir.appendingPathComponent("refs/tags"))
    }

    deinit {
        sources.forEach { $0.cancel() }
        pendingRefresh?.cancel()
    }

    /// Manually trigger a debounced refresh. Useful from `didBecomeActive`.
    func poke() { scheduleRefresh() }

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

    private func scheduleRefresh() {
        // If we're mid-refresh, the in-flight task will already pick up the
        // newest state when it completes. No need to queue another.
        if isRefreshing { return }
        // Ignore events that arrive immediately after our own refresh —
        // those are git's own mtime jiggling, not real external work.
        if Date().timeIntervalSince(lastRefresh) < Self.cooldown { return }

        pendingRefresh?.cancel()
        let delay = Self.debounce
        pendingRefresh = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            self.isRefreshing = true
            await self.onChange()
            self.lastRefresh = Date()
            self.isRefreshing = false
        }
    }
}
