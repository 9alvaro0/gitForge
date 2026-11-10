import Foundation

/// The local error log at `~/Library/Logs/gitForge/gitForge.log` (issue #1):
/// errors gitForge shows the user and git commands that fail, so a bug
/// report can carry them. Complements OSLog, which stays the place for
/// verbose traces (`Diagnostics`).
///
/// Privacy: every entry goes through `LogSanitizer` (URL credentials,
/// account tokens, token-shaped strings, home folder) before it is written,
/// and the file never leaves the Mac unless the user exports it.
///
/// Callers never wait: entries are timestamped on the spot, then sanitized
/// and written on a private serial queue at utility priority. Size is
/// bounded by `RotatingLogFile` (5 files of 1 MB).
nonisolated final class AppLog: @unchecked Sendable {
    enum Level: String, Sendable {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    static let maxFileBytes = 1_048_576
    static let archiveCount = 4
    /// One entry is cut at this many bytes (a huge stderr, a pasted diff).
    static let maxEntryBytes = 8 * 1024

    /// `~/Library/Logs/gitForge`. The app isn't sandboxed, so this is the
    /// user's real Logs folder, the one Console.app lists.
    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/gitForge", isDirectory: true)
    }

    /// The app's log. Disabled while hosting unit tests, so the git
    /// failures the suite provokes on purpose don't land in the developer's
    /// real log.
    static let shared = AppLog(directory: defaultDirectory,
                               isEnabled: !isHostingTests(ProcessInfo.processInfo.environment))

    /// Same check as `AppLauncher.isRunningTests`: Xcode / xcodebuild set
    /// `XCTest…` variables in the process hosting a test bundle.
    static func isHostingTests(_ environment: [String: String]) -> Bool {
        environment.keys.contains { $0.hasPrefix("XCTest") }
    }

    let directory: URL
    let isEnabled: Bool
    private let file: RotatingLogFile
    private let queue = DispatchQueue(label: "com.warwarelabs.gitForge.app-log", qos: .utility)
    private let now: @Sendable () -> Date
    private let homeDirectory: String

    init(directory: URL,
         maxFileBytes: Int = AppLog.maxFileBytes,
         archiveCount: Int = AppLog.archiveCount,
         isEnabled: Bool = true,
         homeDirectory: String = NSHomeDirectory(),
         now: @escaping @Sendable () -> Date = Date.init) {
        self.directory = directory
        self.isEnabled = isEnabled
        self.file = RotatingLogFile(directory: directory, maxFileBytes: maxFileBytes, archiveCount: archiveCount)
        self.homeDirectory = homeDirectory
        self.now = now
    }

    var currentFileURL: URL { file.currentURL }

    func log(_ level: Level, category: String, _ message: String) {
        guard isEnabled else { return }
        let date = now()
        queue.async { [self] in
            let entry = Self.format(date: date, level: level, category: category,
                                    message: LogSanitizer.sanitize(message, homeDirectory: homeDirectory))
            // Nowhere to report a failure to write the log; OSLog still has
            // the original error.
            try? file.append(entry)
        }
    }

    func error(_ message: String, category: String) {
        log(.error, category: category, message)
    }

    func info(_ message: String, category: String) {
        log(.info, category: category, message)
    }

    /// A git command that exited non-zero. Arguments and stderr are
    /// sanitized with the rest of the entry, on the log's queue.
    func gitFailure(args: [String], exitCode: Int32, stderr: String, duration: TimeInterval) {
        guard isEnabled, !Self.isProbeAnswer(exitCode: exitCode, stderr: stderr) else { return }
        let ms = Int((duration * 1000).rounded())
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = trimmed.isEmpty ? "(no error output)" : trimmed
        log(.error, category: "git", "git \(args.joined(separator: " ")) exited \(exitCode) in \(ms) ms\n\(detail)")
    }

    /// Exit 1 with nothing on stderr is git answering "no" to a question
    /// gitForge asks all the time (`config --get` of an unset key,
    /// `rev-parse --verify --quiet` of a missing ref, `diff --quiet`), not a
    /// failure. Logging those would bury the real ones.
    static func isProbeAnswer(exitCode: Int32, stderr: String) -> Bool {
        exitCode == 1 && stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Waits for pending entries and flushes them to disk, then returns the
    /// log files oldest first. Blocks: call it off the main actor.
    func flushedFilesOldestFirst() -> [URL] {
        queue.sync {
            file.synchronize()
            return file.filesOldestFirst
        }
    }

    // MARK: Format

    /// `2026-11-10T09:41:07.312+01:00 ERROR [git] message`, one line;
    /// further lines of a multi-line message are indented four spaces so an
    /// entry is easy to tell apart from the next one.
    static func format(date: Date, level: Level, category: String, message: String,
                       timeZone: TimeZone = .current) -> String {
        let stamp = date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: timeZone))
        let body = truncated(message, toBytes: maxEntryBytes)
            // `\r\n` is a single Character, so split on any newline.
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .joined(separator: "\n    ")
        return "\(stamp) \(level.rawValue) [\(category)] \(body)\n"
    }

    /// Cuts `text` at a character boundary so its UTF-8 form fits `limit`.
    static func truncated(_ text: String, toBytes limit: Int) -> String {
        guard text.utf8.count > limit else { return text }
        let marker = " … [truncated]"
        let budget = limit - marker.utf8.count
        var used = 0
        var end = text.startIndex
        for index in text.indices {
            let size = text[index].utf8.count
            if used + size > budget { break }
            used += size
            end = text.index(after: index)
        }
        return String(text[..<end]) + marker
    }
}
