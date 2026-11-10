import Foundation

/// Builds the file Help › Export Logs… saves: a header with what a bug
/// report needs (app, macOS and git versions) and what the file contains,
/// then the log files in chronological order, sanitized once more in case a
/// token was registered after an older entry was written.
///
/// The text is English on purpose: it is read by whoever triages the
/// report. The save panel explains it to the user in their language.
nonisolated enum LogExport {
    struct Environment: Sendable, Equatable {
        var appVersion: String
        var appBuild: String
        var macOSVersion: String
        var gitVersion: String
        var exportedAt: Date
    }

    static let separator = String(repeating: "-", count: 72)

    static func header(_ environment: Environment, timeZone: TimeZone = .current) -> String {
        let stamp = environment.exportedAt.formatted(Date.ISO8601FormatStyle(timeZone: timeZone))
        return """
        gitForge log export
        Exported: \(stamp)
        App: gitForge \(environment.appVersion) (\(environment.appBuild))
        macOS: \(environment.macOSVersion)
        git: \(environment.gitVersion)

        What this file contains: errors gitForge showed and git commands that
        failed (the command, its exit code and git's error output), with their
        time. Paths in your home folder are shown as ~. Tokens, passwords and
        credentials in URLs are replaced by \(LogSanitizer.mask). gitForge
        sends nothing anywhere: this file only leaves your Mac if you share it.
        Read it before attaching it to a bug report.
        \(separator)

        """
    }

    /// The full export: header plus every log file, oldest first.
    static func report(environment: Environment, logFiles: [URL],
                       homeDirectory: String = NSHomeDirectory(),
                       timeZone: TimeZone = .current) -> String {
        let body = logFiles
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .joined()
        let entries = body.isEmpty ? "(The log is empty: no errors recorded.)\n" : body
        return LogSanitizer.sanitize(header(environment, timeZone: timeZone) + entries,
                                     homeDirectory: homeDirectory)
    }

    /// `gitForge-logs-2026-11-10-0941.log`
    static func suggestedFileName(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let stamp = String(format: "%04d-%02d-%02d-%02d%02d",
                           parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
                           parts.hour ?? 0, parts.minute ?? 0)
        return "gitForge-logs-\(stamp).log"
    }

    /// The running app and system; `gitVersion` comes from `git --version`.
    static func currentEnvironment(gitVersion: String, bundle: Bundle = .main,
                                   exportedAt: Date = Date()) -> Environment {
        Environment(
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            appBuild: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            gitVersion: gitVersion,
            exportedAt: exportedAt
        )
    }
}
