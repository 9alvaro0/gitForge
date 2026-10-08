import Foundation
import CoreServices
import os

/// Recursive `FSEventStream` over one or more directory trees. Path-based, so
/// it keeps working when a watched file is replaced by `rename(2)` — which
/// is how git writes `HEAD`, `packed-refs` and every ref. (The previous
/// `DispatchSource` watchers were bound to the original inode and went dark
/// after the first checkout.)
///
/// Every batch is handed to `onEvents` on `queue`, off the main actor; the
/// caller filters and hops to the main actor itself.
///
/// The stream retains a small `Callback` box through its context's
/// retain/release callbacks rather than holding an unretained pointer to
/// `self`, so a batch in flight on `queue` while the owner deinits can never
/// touch freed memory.
nonisolated final class FileEventStream: @unchecked Sendable {
    /// What one FSEvents batch looks like to the caller.
    struct Batch: Sendable {
        let paths: [String]
        /// FSEvents coalesced or dropped events (`MustScanSubDirs`, kernel or
        /// user drops): individual paths are no longer trustworthy and the
        /// caller should assume anything changed.
        let mustRescan: Bool
    }

    private static let logger = Logger(subsystem: "com.warwarelabs.gitForge", category: "fs-watcher")

    private final class Callback {
        let handler: @Sendable (Batch) -> Void
        init(_ handler: @escaping @Sendable (Batch) -> Void) { self.handler = handler }
    }

    /// `stream` is written once in `init` and read in `deinit` only.
    private let stream: FSEventStreamRef
    private let queue = DispatchQueue(label: "com.warwarelabs.gitForge.fsevents", qos: .utility)

    /// - Parameters:
    ///   - latency: coalescing window inside FSEvents before the kernel
    ///     delivers a batch. Half a second matches what Xcode and Finder use.
    init?(paths: [String],
          latency: CFTimeInterval = 0.5,
          onEvents: @escaping @Sendable (Batch) -> Void) {
        let box = Unmanaged.passRetained(Callback(onEvents)).toOpaque()
        var context = FSEventStreamContext(
            version: 0,
            info: box,
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<Callback>.fromOpaque(info).retain()
                return UnsafeRawPointer(info)
            },
            release: { info in
                guard let info else { return }
                Unmanaged<Callback>.fromOpaque(info).release()
            },
            copyDescription: nil
        )
        // `UseCFTypes`   — eventPaths arrives as a CFArray of CFString,
        //                  toll-free-bridgeable to [String]. Without it the
        //                  parameter is a raw C `char**` and bridging via
        //                  NSArray crashes.
        // `IgnoreSelf`   — drops events caused by our own process (files the
        //                  app writes itself); git subprocesses still count.
        // `FileEvents`   — per-file granularity instead of per-directory.
        // `NoDefer`      — deliver the first event of a batch immediately
        //                  instead of waiting `latency` for more.
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes
            | kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagIgnoreSelf
            | kFSEventStreamCreateFlagNoDefer
        )
        let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, count, rawPaths, rawFlags, _ in
                guard let info else { return }
                // With `UseCFTypes` the eventPaths parameter is a CFArrayRef
                // of CFString. Bridge through CFArray (not raw NSArray) so a
                // misconfigured stream surfaces as a clean nil instead of a
                // memory-stomping bitcast.
                let cfArray = Unmanaged<CFArray>.fromOpaque(rawPaths).takeUnretainedValue()
                guard let paths = cfArray as? [String] else { return }
                let rescanMask = FSEventStreamEventFlags(
                    kFSEventStreamEventFlagMustScanSubDirs
                    | kFSEventStreamEventFlagUserDropped
                    | kFSEventStreamEventFlagKernelDropped
                )
                let mustRescan = (0..<count).contains { rawFlags[$0] & rescanMask != 0 }
                Unmanaged<Callback>.fromOpaque(info).takeUnretainedValue()
                    .handler(Batch(paths: paths, mustRescan: mustRescan))
            },
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        )
        // The stream took its own retain through `context.retain`; balance
        // the one taken when the box was created.
        Unmanaged<Callback>.fromOpaque(box).release()
        guard let created else {
            Self.logger.error("FSEventStreamCreate failed for \(paths, privacy: .public)")
            return nil
        }
        FSEventStreamSetDispatchQueue(created, queue)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            Self.logger.error("FSEventStreamStart failed for \(paths, privacy: .public)")
            return nil
        }
        stream = created
    }

    deinit {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}

/// Decides which filesystem events mean "the repository changed". Pure and
/// path-only so it can be unit-tested without a live stream.
///
/// - Working tree: everything outside the git directories counts (IDE saves,
///   formatters, generated files).
/// - Git directories: only state git *publishes* — `HEAD`, refs, packed-refs
///   and the in-progress markers (merge / rebase / cherry-pick / revert /
///   bisect). `index`, `objects/`, `logs/`, `FETCH_HEAD` and lock files are
///   ignored: our own read-only `git status` rewrites the index and every
///   fetch rewrites FETCH_HEAD, so watching those would feed back into a
///   refresh loop.
nonisolated struct RepositoryEventFilter: Sendable {
    private let worktree: String
    private let gitDirectories: [String]

    private static let gitStateFiles: Set<String> = [
        "head", "packed-refs", "merge_head", "cherry_pick_head", "revert_head", "bisect_log",
    ]
    private static let gitStatePrefixes = ["refs/", "rebase-merge", "rebase-apply"]

    init(worktree: String, gitDirectories: [String]) {
        self.worktree = Self.normalized(worktree)
        // Longest first, so a linked worktree's gitdir
        // (`<main>/.git/worktrees/x`) wins over the common dir it sits in.
        self.gitDirectories = gitDirectories.map(Self.normalized)
            .sorted { $0.count > $1.count }
    }

    func isRelevant(_ batch: FileEventStream.Batch) -> Bool {
        batch.mustRescan || batch.paths.contains(where: isRelevant)
    }

    func isRelevant(_ path: String) -> Bool {
        let path = Self.normalized(path)
        for dir in gitDirectories where path == dir || path.hasPrefix(dir + "/") {
            return Self.isRelevantGitPath(String(path.dropFirst(dir.count + 1)))
        }
        return path.hasPrefix(worktree + "/")
    }

    private static func isRelevantGitPath(_ relative: String) -> Bool {
        if relative.hasSuffix(".lock") { return false }
        if gitStateFiles.contains(relative) { return true }
        return gitStatePrefixes.contains { relative.hasPrefix($0) }
    }

    /// FSEvents reports canonical paths, compared case-insensitively since
    /// APFS volumes are case-insensitive by default.
    private static func normalized(_ path: String) -> String {
        var path = path.lowercased()
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }
}

extension URL {
    /// Symlink-free absolute path as FSEvents reports it (`/tmp/x` →
    /// `/private/tmp/x`). `resolvingSymlinksInPath()` can't be used: it
    /// strips `/private` back off.
    nonisolated var canonicalFileSystemPath: String {
        let path = self.path(percentEncoded: false)
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
