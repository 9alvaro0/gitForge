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
    private static let debounce: TimeInterval = 0.35

    private var sources: [DispatchSourceFileSystemObject] = []
    private var pendingRefresh: Task<Void, Never>?
    private let onChange: @MainActor () async -> Void

    init(repository: URL, onChange: @escaping @MainActor () async -> Void) {
        self.onChange = onChange
        let gitDir = repository.appendingPathComponent(".git")
        watch(gitDir.appendingPathComponent("HEAD"))
        watch(gitDir.appendingPathComponent("index"))
        watch(gitDir.appendingPathComponent("refs"))
        watch(gitDir.appendingPathComponent("packed-refs"))
        watch(gitDir.appendingPathComponent("FETCH_HEAD"))
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
        guard FileManager.default.fileExists(atPath: path) else {
            // .git/FETCH_HEAD doesn't exist until the first fetch — that's fine;
            // we'll see it via the refs/ directory watch instead.
            return
        }
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            Self.logger.error("watch(\(path, privacy: .public)) open failed")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend, .attrib],
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
        pendingRefresh?.cancel()
        let delay = Self.debounce
        let action = onChange
        pendingRefresh = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            if Task.isCancelled { return }
            await action()
        }
    }
}
