import Foundation
import Testing
@testable import gitForge

@Suite("ShellStatus")
struct ShellStatusTests {

    @Test("Subtitle shows the branch, with arrows only for non-zero counts")
    func subtitle() {
        #expect(ShellStatus.subtitle(branch: "main", ahead: 0, behind: 0) == "main")
        #expect(ShellStatus.subtitle(branch: "main", ahead: 2, behind: 0) == "main  ↑2")
        #expect(ShellStatus.subtitle(branch: "feature/x", ahead: 2, behind: 5) == "feature/x  ↑2 ↓5")
        #expect(ShellStatus.subtitle(branch: "main", ahead: 0, behind: 3) == "main  ↓3")
    }

    @Test("A detached HEAD is named, never blank")
    func detached() {
        #expect(ShellStatus.subtitle(branch: nil, ahead: 0, behind: 0) == "Detached HEAD")
    }

    @Test("Fetch help says when the last fetch ran", arguments: [
        (nil as TimeInterval?, "Fetch from remotes · never fetched"),
        (20, "Fetch from remotes · last fetched just now"),
        (180, "Fetch from remotes · last fetched 3 min ago"),
        (7_200, "Fetch from remotes · last fetched 2 h ago"),
        (259_200, "Fetch from remotes · last fetched 3 d ago"),
    ])
    func fetchHelp(age: TimeInterval?, expected: String) {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let last = age.map { now.addingTimeInterval(-$0) }
        #expect(ShellStatus.fetchHelp(lastFetch: last, now: now, online: true) == expected)
    }

    @Test("Offline wins over the last fetch")
    func offline() {
        #expect(ShellStatus.fetchHelp(lastFetch: Date(), now: Date(), online: false) == "Offline")
    }

    @Test("Initials take the first letters of the first two words or camel-case humps",
          arguments: [("gitForge", "gf"), ("my-app", "ma"), ("my_app", "ma"), ("repo", "re"),
                      ("x", "x"), ("Ironway", "ir"), ("design system kit", "ds"), ("2048", "20")])
    func initials(name: String, expected: String) {
        #expect(ShellStatus.initials(for: name) == expected)
    }

    @Test("A name with no letters or digits still gets a mark")
    func initialsFallback() {
        #expect(ShellStatus.initials(for: "---") == "?")
        #expect(ShellStatus.initials(for: "") == "?")
    }
}
