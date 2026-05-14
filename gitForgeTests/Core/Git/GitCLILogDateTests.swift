import Foundation
import Testing
@testable import gitForge

/// `%aI` produces ISO 8601 dates; a corrupt or non-conforming value used to
/// fall through to `Date()` (now), floating bad commits to the top of the
/// log. The sentinel keeps them at the bottom and identifiable.
@Suite("GitCLI.parseLog — date robustness")
struct GitCLILogDateTests {

    private let sep = "\u{1F}"

    private func line(date: String,
                      sha: String = "abc1234",
                      parents: String = "",
                      name: String = "Alvaro",
                      email: String = "alvaro@example.com",
                      subject: String = "hello") -> String {
        [sha, parents, name, email, date, subject].joined(separator: sep)
    }

    @Test("Standard ISO 8601 timestamp parses correctly")
    func parsesStandardISO() {
        let stdout = line(date: "2026-05-13T10:00:00Z")
        let commits = GitCLI.parseLog(stdout)
        #expect(commits.count == 1)
        #expect(commits.first?.authorDate != GitCLI.unknownAuthorDate)
    }

    @Test("ISO 8601 with offset still parses")
    func parsesOffsetISO() {
        let stdout = line(date: "2026-05-13T12:00:00+02:00")
        let commits = GitCLI.parseLog(stdout)
        #expect(commits.count == 1)
        #expect(commits.first?.authorDate != GitCLI.unknownAuthorDate)
    }

    @Test("Unparseable date falls to epoch sentinel, NOT to `now`")
    func fallsToSentinel() {
        let stdout = line(date: "not-a-date")
        let commits = GitCLI.parseLog(stdout)
        #expect(commits.count == 1)
        #expect(commits.first?.authorDate == GitCLI.unknownAuthorDate)
    }

    @Test("Empty date string falls to sentinel")
    func emptyDateFallsToSentinel() {
        let stdout = line(date: "")
        let commits = GitCLI.parseLog(stdout)
        #expect(commits.first?.authorDate == GitCLI.unknownAuthorDate)
    }

    @Test("Sentinel is epoch 1970-01-01, so it sorts before any real commit")
    func sentinelSortsBelowRealDates() {
        let stdout = [
            line(date: "2026-05-13T10:00:00Z", sha: "real"),
            line(date: "garbage", sha: "broken"),
        ].joined(separator: "\n")
        let commits = GitCLI.parseLog(stdout)
        let sorted = commits.sorted { $0.authorDate < $1.authorDate }
        #expect(sorted.first?.sha == "broken")
        #expect(sorted.last?.sha == "real")
    }
}
