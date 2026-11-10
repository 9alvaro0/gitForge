import Foundation
import Testing
@testable import gitForge

@Suite("AppLog")
struct AppLogTests {
    private static let fixedDate = Date(timeIntervalSince1970: 1_762_767_667.312)

    private func makeLog(maxFileBytes: Int = AppLog.maxFileBytes, isEnabled: Bool = true) -> AppLog {
        let date = Self.fixedDate
        return AppLog(directory: TemporaryDirectories.make("app-log"), maxFileBytes: maxFileBytes,
                      isEnabled: isEnabled, homeDirectory: "/Users/alice", now: { date })
    }

    private func contents(_ log: AppLog) -> String {
        log.flushedFilesOldestFirst()
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .joined()
    }

    @Test("An entry is one timestamped line; extra lines are indented")
    func format() {
        let line = AppLog.format(date: Self.fixedDate, level: .error, category: "git",
                                 message: "first\nsecond\r\nthird",
                                 timeZone: TimeZone(identifier: "UTC")!)
        #expect(line == "2025-11-10T09:41:07.312Z ERROR [git] first\n    second\n    third\n")
    }

    @Test("Writes are sanitized before they reach the file")
    func sanitizesOnWrite() {
        let log = makeLog()
        log.error("push to https://bob:hunter2token@github.com/org/repo.git from /Users/alice/repo failed",
                  category: "toast")
        let text = contents(log)
        #expect(text.contains("ERROR [toast] push to https://****@github.com/org/repo.git from ~/repo failed"))
        #expect(!text.contains("hunter2token"))
        #expect(!text.contains("/Users/alice"))
    }

    @Test("A git failure records the command, exit code, duration and redacted stderr")
    func gitFailure() {
        let log = makeLog()
        SecretRedactor.shared.register("test-app-log-token-1")
        log.gitFailure(args: ["push", "https://x:test-app-log-token-1@host/r.git"], exitCode: 128,
                       stderr: "fatal: Authentication failed for 'https://x:test-app-log-token-1@host/r.git'\n",
                       duration: 0.4204)
        let text = contents(log)
        #expect(text.contains("[git] git push https://****@host/r.git exited 128 in 420 ms\n    fatal: Authentication failed for 'https://****@host/r.git'\n"))
        #expect(!text.contains("test-app-log-token-1"))
    }

    @Test("Exit 1 with empty stderr is a probe answer, not logged; other failures are")
    func probeAnswers() {
        #expect(AppLog.isProbeAnswer(exitCode: 1, stderr: " \n"))
        #expect(!AppLog.isProbeAnswer(exitCode: 1, stderr: "error: something"))
        #expect(!AppLog.isProbeAnswer(exitCode: 128, stderr: ""))

        let log = makeLog()
        log.gitFailure(args: ["config", "--get", "user.signingkey"], exitCode: 1, stderr: "", duration: 0.01)
        log.gitFailure(args: ["status"], exitCode: 128, stderr: "", duration: 0.01)
        let text = contents(log)
        #expect(!text.contains("config --get"))
        #expect(text.contains("git status exited 128 in 10 ms\n    (no error output)"))
    }

    @Test("Huge entries are cut at a character boundary")
    func truncation() {
        let cut = AppLog.truncated(String(repeating: "é", count: 20), toBytes: 21)
        #expect(cut.utf8.count <= 21)
        #expect(cut.hasPrefix("éé"))
        #expect(cut.hasSuffix(" … [truncated]"))
        #expect(AppLog.truncated("short", toBytes: 20) == "short")

        let log = makeLog()
        log.error(String(repeating: "x", count: AppLog.maxEntryBytes * 3), category: "toast")
        #expect(contents(log).utf8.count < AppLog.maxEntryBytes + 100)
    }

    @Test("Entries keep their order and the log rotates under load")
    func orderAndRotation() {
        let log = makeLog(maxFileBytes: 2_000)
        for index in 0..<200 { log.error("entry \(index)", category: "toast") }
        let files = log.flushedFilesOldestFirst()
        #expect(files.count == AppLog.archiveCount + 1)
        let text = contents(log)
        #expect(text.contains("entry 199\n"))
        #expect(text.range(of: "entry 198\n")!.lowerBound < text.range(of: "entry 199\n")!.lowerBound)
    }

    @Test("A disabled log writes nothing")
    func disabled() {
        let log = makeLog(isEnabled: false)
        log.error("nope", category: "toast")
        log.gitFailure(args: ["status"], exitCode: 128, stderr: "fatal", duration: 0)
        #expect(log.flushedFilesOldestFirst().isEmpty)
    }

    @Test("The shared log is disabled when the process hosts XCTest")
    func testHostDetection() {
        #expect(AppLog.isHostingTests(["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"]))
        #expect(!AppLog.isHostingTests(["HOME": "/Users/alice"]))
    }
}
