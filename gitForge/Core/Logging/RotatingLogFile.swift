import Foundation

/// An append-only text file that rotates by size: when the next write would
/// push `<name>.log` past `maxFileBytes`, it becomes `<name>.1.log`, the
/// older archives shift up by one and the oldest beyond `archiveCount` is
/// deleted. Total disk use stays under `maxFileBytes × (archiveCount + 1)`.
///
/// Not thread-safe: `AppLog` only touches it from its serial queue. The
/// folder is created `0700` and the files `0600`, so other users on the Mac
/// can't read them.
nonisolated final class RotatingLogFile {
    let directory: URL
    let baseName: String
    let maxFileBytes: Int
    let archiveCount: Int

    private let fileManager = FileManager.default
    private var handle: FileHandle?
    private var currentSize = 0

    init(directory: URL, baseName: String = "gitForge", maxFileBytes: Int, archiveCount: Int) {
        precondition(maxFileBytes > 0 && archiveCount >= 0)
        self.directory = directory
        self.baseName = baseName
        self.maxFileBytes = maxFileBytes
        self.archiveCount = archiveCount
    }

    deinit { try? handle?.close() }

    /// `<name>.log`, the file being written.
    var currentURL: URL { directory.appendingPathComponent("\(baseName).log") }

    /// `<name>.<index>.log`; 1 is the most recent archive.
    func archiveURL(_ index: Int) -> URL {
        directory.appendingPathComponent("\(baseName).\(index).log")
    }

    /// The files that exist, oldest first, so reading them in order gives
    /// the log in chronological order.
    var filesOldestFirst: [URL] {
        let candidates = (1...max(archiveCount, 1)).reversed().map(archiveURL) + [currentURL]
        return candidates.filter { fileManager.fileExists(atPath: $0.path) }
    }

    /// Appends `text` as is (the caller adds the newline). A single write
    /// larger than `maxFileBytes` still goes into one file, alone; callers
    /// cap entry size well below the limit.
    func append(_ text: String) throws {
        let data = Data(text.utf8)
        try openIfNeeded()
        if currentSize > 0, currentSize + data.count > maxFileBytes {
            try rotate()
            try openIfNeeded()
        }
        try handle?.write(contentsOf: data)
        currentSize += data.count
    }

    /// Flushes to disk; used before an export reads the files.
    func synchronize() {
        try? handle?.synchronize()
    }

    /// Moves the current file into the archives now.
    func rotate() throws {
        try? handle?.close()
        handle = nil
        currentSize = 0
        guard archiveCount > 0 else {
            try? fileManager.removeItem(at: currentURL)
            return
        }
        try? fileManager.removeItem(at: archiveURL(archiveCount))
        for index in stride(from: archiveCount - 1, through: 1, by: -1) {
            let source = archiveURL(index)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try fileManager.moveItem(at: source, to: archiveURL(index + 1))
        }
        if fileManager.fileExists(atPath: currentURL.path) {
            try fileManager.moveItem(at: currentURL, to: archiveURL(1))
        }
    }

    private func openIfNeeded() throws {
        // Someone may have deleted the file or the folder (Finder, a
        // cleaner) while it was open: writes would go to an unlinked inode
        // and be lost, so start a new file instead.
        if handle != nil, !fileManager.fileExists(atPath: currentURL.path) {
            try? handle?.close()
            handle = nil
        }
        guard handle == nil else { return }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        if !fileManager.fileExists(atPath: currentURL.path) {
            guard fileManager.createFile(atPath: currentURL.path, contents: nil,
                                         attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: currentURL.path])
            }
        }
        let opened = try FileHandle(forWritingTo: currentURL)
        currentSize = Int(try opened.seekToEnd())
        handle = opened
    }
}
