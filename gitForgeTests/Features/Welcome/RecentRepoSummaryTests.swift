import Foundation
import Testing
@testable import gitForge

@Suite("RecentRepoSummary")
struct RecentRepoSummaryTests {

    @Test("Branch, changes and ahead/behind are read; changes come first in the label")
    func full() {
        let s = RecentRepoSummary.parse("## main...origin/main [ahead 1, behind 2]\n M a.swift\n?? b.swift\nA  c.swift\n")
        #expect(s == RecentRepoSummary(branch: "main", changed: 3, ahead: 1, behind: 2))
        #expect(s.label == "3 changed")
    }

    @Test("Clean, ahead, behind and both")
    func labels() {
        #expect(RecentRepoSummary.parse("## main...origin/main\n").label == "Clean")
        #expect(RecentRepoSummary.parse("## main...origin/main [ahead 1]\n").label == "↑ 1 ahead")
        #expect(RecentRepoSummary.parse("## main...origin/main [behind 12]\n").label == "↓ 12 behind")
        #expect(RecentRepoSummary.parse("## main...origin/main [ahead 1, behind 2]\n").label == "↑1 ↓2")
        #expect(RecentRepoSummary.parse("## feature/x\n").branch == "feature/x")
    }

    @Test("Detached HEAD and a branch with no commits")
    func special() {
        #expect(RecentRepoSummary.parse("## HEAD (no branch)\n M a\n").branch == nil)
        #expect(RecentRepoSummary.parse("## No commits yet on main\n").branch == "main")
    }
}
