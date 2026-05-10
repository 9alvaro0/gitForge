import Foundation
import CoreServices
import os

/// Recursive working-tree watcher backed by `FSEventStream`. Catches the case
/// `RepositoryWatcher` misses by design: external edits to tracked files
/// (IDE saves, editor formatters, build artefacts the user cares about) that
/// never touch `.git/` and therefore wouldn't move any of the dispatch
/// sources we set up there.
///
/// Events are coalesced by FSEvents itself (`latency`) and then bounced to
/// the main actor where the caller's existing debounce/cooldown takes over.
final class WorkingTreeWatcher {
    private static let logger = Logger(subsystem: "com.warwarelabs.gitForge", category: "fs-watcher")
    /// Coalescing window inside FSEvents before the kernel delivers a batch.
    /// Half a second matches what apps like Xcode and Finder use — short
    /// enough to feel live, long enough to flatten a multi-file save.
    private static let latency: CFTimeInterval = 0.5

    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.warwarelabs.gitForge.fsevents", qos: .utility)
    private let onChange: @MainActor () -> Void

    init?(root: URL, onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        let path = root.path(percentEncoded: false)
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        // `UseCFTypes`   — eventPaths arrives as a CFArray of CFString,
        //                  toll-free-bridgeable to [String]. Without it
        //                  the parameter is a raw C `char**` and bridging
        //                  via NSArray crashes.
        // `IgnoreSelf`   — drops events caused by our own process. Git ops
        //                  the app runs already trigger refreshes through
        //                  their own code paths; seeing them again is noise.
        // `FileEvents`   — per-file granularity instead of per-directory.
        // `NoDefer`      — deliver the first event of a batch immediately
        //                  instead of waiting `latency` for more.
        let flags: FSEventStreamCreateFlags =
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes) |
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents) |
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagIgnoreSelf) |
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, count, paths, flags, ids in
                guard let info else { return }
                // With `UseCFTypes` the eventPaths parameter is a CFArrayRef
                // of CFString. Bridge through CFArray (not raw NSArray) so
                // a misconfigured stream surfaces as a clean nil instead of
                // a memory-stomping bitcast.
                let cfArray = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue()
                guard let strings = cfArray as? [String] else { return }
                let watcher = Unmanaged<WorkingTreeWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.handle(paths: strings, flags: flags, count: count, ids: ids)
            },
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Self.latency,
            flags
        ) else {
            Self.logger.error("FSEventStreamCreate failed for \(path, privacy: .public)")
            return nil
        }
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            Self.logger.error("FSEventStreamStart failed for \(path, privacy: .public)")
            return nil
        }
        self.stream = stream
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    private func handle(
        paths: [String],
        flags: UnsafePointer<FSEventStreamEventFlags>,
        count: Int,
        ids: UnsafePointer<FSEventStreamEventId>
    ) {
        // FSEvents fires for `.git/` mutations too (commits we run ourselves,
        // git's own housekeeping). The dedicated DispatchSource watcher in
        // RepositoryWatcher already covers those, and the shared scheduler
        // dedupes via debounce — so we don't need to filter here for
        // correctness. We do filter to cut the wakeup count: at high event
        // rates (a dependency install hitting node_modules) the bounce-to-
        // main alone adds up.
        for path in paths {
            if path.contains("/.git/") || path.hasSuffix("/.git") { continue }
            Task { @MainActor [onChange] in onChange() }
            return
        }
    }
}
