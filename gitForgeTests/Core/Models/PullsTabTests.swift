import Testing
@testable import gitForge

/// The tabs of the Pull requests section (U1 Ruling 1).
@Suite("Pull requests tabs")
struct PullsTabTests {
    @Test("With a repository open all four tabs show, in order; without one, only Team and Mine")
    func available() {
        #expect(PullsTab.available(hasRepository: true) == [.team, .mine, .open, .closed])
        #expect(PullsTab.available(hasRepository: false) == [.team, .mine])
    }

    @Test("The saved tab shows, but Open and Closed give way to Team without a repository")
    func shown() {
        #expect(PullsTab.shown(.closed, hasRepository: false) == .team)
        #expect(PullsTab.shown(.open, hasRepository: false) == .team)
        #expect(PullsTab.shown(.closed, hasRepository: true) == .closed)
        #expect(PullsTab.shown(.open, hasRepository: true) == .open)
        #expect(PullsTab.shown(.mine, hasRepository: false) == .mine)
        #expect(PullsTab.shown(.team, hasRepository: false) == .team)
    }

    @Test("Team and Mine are the inbox's halves; Open and Closed are the repository's lists")
    func halvesAndLists() {
        #expect(PullsTab.team.half == .team)
        #expect(PullsTab.mine.half == .mine)
        #expect(PullsTab.open.half == nil)
        #expect(PullsTab.closed.half == nil)
        #expect(PullsTab.team.repositoryList == nil)
        #expect(PullsTab.mine.repositoryList == nil)
        #expect(PullsTab.open.repositoryList == .open)
        #expect(PullsTab.closed.repositoryList == .closed)
    }

    @Test("A half and a repository list make one tab: the list wins")
    func fromHalfAndList() {
        #expect(PullsTab(half: .team, repositoryList: nil) == .team)
        #expect(PullsTab(half: .mine, repositoryList: nil) == .mine)
        #expect(PullsTab(half: .mine, repositoryList: .open) == .open)
        #expect(PullsTab(half: .team, repositoryList: .closed) == .closed)
    }

    @Test("The titles reuse the words of the inbox's halves and the repository's scopes")
    func titles() {
        #expect(PullsTab.team.title == ReviewsFilter.team.title)
        #expect(PullsTab.mine.title == ReviewsFilter.mine.title)
        #expect(PullsTab.open.title == PullListScope.open.title)
        #expect(PullsTab.closed.title == PullListScope.closed.title)
    }

    @Test("A saved name that is no tab reads as nothing", arguments: ["reviews", "", "x"])
    func unknownRawValue(raw: String) {
        #expect(PullsTab(rawValue: raw) == nil)
    }

    @Test("The names saved on disk are the tab's own")
    func rawValues() {
        #expect(PullsTab.allCases.map(\.rawValue) == ["team", "mine", "open", "closed"])
    }
}
