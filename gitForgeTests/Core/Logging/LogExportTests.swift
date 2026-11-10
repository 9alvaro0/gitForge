import Foundation
import Testing
@testable import gitForge

@Suite("LogExport")
struct LogExportTests {
    private let utc = TimeZone(identifier: "UTC")!
    private let environment = LogExport.Environment(
        appVersion: "1.9.0", appBuild: "42",
        macOSVersion: "Version 26.1 (Build 25B78)",
        gitVersion: "git version 2.50.1 (Apple Git-155)",
        exportedAt: Date(timeIntervalSince1970: 1_762_767_667))

    @Test("The header names the versions and says what the file contains")
    func header() {
        let text = LogExport.header(environment, timeZone: utc)
        #expect(text.hasPrefix("gitForge log export\nExported: 2025-11-10T09:41:07Z\n"))
        #expect(text.contains("App: gitForge 1.9.0 (42)\n"))
        #expect(text.contains("macOS: Version 26.1 (Build 25B78)\n"))
        #expect(text.contains("git: git version 2.50.1 (Apple Git-155)\n"))
        #expect(text.contains("What this file contains:"))
        #expect(text.contains("sends nothing anywhere"))
    }

    @Test("The report joins the files oldest first and sanitizes them again")
    func report() throws {
        let dir = TemporaryDirectories.make("log-export")
        let log = RotatingLogFile(directory: dir, maxFileBytes: 40, archiveCount: 2)
        try log.append("older entry from /Users/alice/repo\n")
        SecretRedactor.shared.register("test-log-export-token-1")
        try log.append("newer entry test-log-export-token-1\n")

        let text = LogExport.report(environment: environment, logFiles: log.filesOldestFirst,
                                    homeDirectory: "/Users/alice", timeZone: utc)
        let older = try #require(text.range(of: "older entry from ~/repo"))
        let newer = try #require(text.range(of: "newer entry ****"))
        #expect(older.lowerBound < newer.lowerBound)
        #expect(!text.contains("test-log-export-token-1"))
        #expect(text.hasPrefix("gitForge log export"))
    }

    @Test("An empty log still exports the header and says it is empty")
    func emptyLog() {
        let text = LogExport.report(environment: environment, logFiles: [], timeZone: utc)
        #expect(text.hasSuffix("(The log is empty: no errors recorded.)\n"))
    }

    @Test("Suggested file name carries the date and time")
    func fileName() {
        #expect(LogExport.suggestedFileName(for: environment.exportedAt, timeZone: utc)
                == "gitForge-logs-2025-11-10-0941.log")
    }
}
