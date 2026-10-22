import Foundation
import Testing
@testable import gitForge

@Suite("Command palette sections")
@MainActor
struct CommandPaletteSectionsTests {

    private static func item(_ kind: CommandPaletteItem.Kind, _ label: String,
                             keywords: [String] = [], number: Int? = nil) -> CommandPaletteItem {
        CommandPaletteItem(kind: kind, label: label, hint: nil, action: .noop, keywords: keywords, number: number)
    }

    @Test("Groups go Actions, Repositories, Pull requests, Branches, Commits, Files; empty ones are left out")
    func order() {
        let items = [Self.item(.file, "a.swift"), Self.item(.commit, "Fix"), Self.item(.command, "Fetch all"),
                     Self.item(.repo, "me/app"), Self.item(.branch, "main"), Self.item(.pull, "Retry")]
        let sections = CommandPaletteSections.build(items: items, query: "")
        #expect(sections.map(\.kind) == [.command, .repo, .pull, .branch, .commit, .file])
        #expect(sections.map(\.kind.title) == ["Actions", "Repositories", "Pull requests", "Branches", "Commits", "Files"])
        let withoutPullsAndBranches = CommandPaletteSections.build(items: items.filter { $0.kind != .branch && $0.kind != .pull }, query: "")
        #expect(withoutPullsAndBranches.map(\.kind) == [.command, .repo, .commit, .file])
    }

    @Test("Without a query: every action and five of each other group")
    func emptyQuery() {
        let items = (0..<8).map { Self.item(.command, "Action \($0)") } + (0..<8).map { Self.item(.branch, "branch-\($0)") }
        let sections = CommandPaletteSections.build(items: items, query: "")
        #expect(sections[0].rows.count == 8)
        #expect(sections[1].rows.map(\.item.label) == (0..<5).map { "branch-\($0)" })
    }

    @Test("With a query: up to six per group, best first, ties in input order")
    func ranked() {
        let items = (0..<9).map { Self.item(.branch, "feature/x\($0)") } + [Self.item(.branch, "fx")]
        let sections = CommandPaletteSections.build(items: items, query: "fx")
        #expect(sections.count == 1)
        #expect(sections[0].rows.count == 6)
        #expect(sections[0].rows.first?.item.label == "fx")
        #expect(Array(sections[0].rows.dropFirst().map(\.item.label)) == (0..<5).map { "feature/x\($0)" })
        #expect(sections[0].rows.first?.match?.indices == [0, 1])
    }

    @Test("Open and Clone are built-in actions")
    func newActions() {
        let actions = CommandPaletteBuilder.builtInCommands.map(\.action)
        #expect(actions.contains(.openRepository))
        #expect(actions.contains(.cloneRepository))
    }

    // MARK: Scopes

    @Test("A scope shows only its group, with up to 50 rows, browsing or searching")
    func scoped() {
        let items = (0..<60).map { Self.item(.branch, "feature/x\($0)") } + [Self.item(.command, "Fetch all")]
        let browsing = CommandPaletteSections.build(items: items, query: "", scope: .only(.branch))
        #expect(browsing.map(\.kind) == [.branch])
        #expect(browsing[0].rows.count == CommandPaletteSections.scopedLimit)
        let searching = CommandPaletteSections.build(items: items, query: "fx", scope: .only(.branch))
        #expect(searching.map(\.kind) == [.branch])
        #expect(searching[0].rows.count == CommandPaletteSections.scopedLimit)
        #expect(CommandPaletteSections.build(items: items, query: "fetch", scope: .only(.branch)).isEmpty)
    }

    @Test("⇥ steps All → Actions → … → Files → All, ⇧⇥ goes back")
    func scopeCycle() {
        var scope = CommandPaletteScope.all
        var seen: [String] = []
        for _ in CommandPaletteScope.ordered {
            scope = scope.next()
            seen.append(scope.title)
        }
        #expect(seen == ["Actions", "Repositories", "Pull requests", "Branches", "Commits", "Files", "All"])
        #expect(CommandPaletteScope.all.previous() == .only(.file))
        #expect(CommandPaletteScope.only(.command).previous() == .all)
    }

    // MARK: Pull requests

    @Test("An exact number ranks first, ahead of a title that merely contains those digits")
    func exactNumberFirst() {
        let items = [Self.item(.pull, "Bump 1482 deps", keywords: ["7"], number: 7),
                     Self.item(.pull, "Retry", keywords: ["482"], number: 482)]
        let sections = CommandPaletteSections.build(items: items, query: "#482")
        #expect(sections.map(\.kind) == [.pull])
        #expect(sections[0].rows.map(\.item.label) == ["Retry", "Bump 1482 deps"])
        #expect(sections[0].rows.first?.match?.score == PaletteSearch.exactNumberScore)
    }

    @Test("A pull request is found by any of its keywords, and the rows keep the title's highlight")
    func keywordsRank() {
        let items = [Self.item(.pull, "Retry on timeout", keywords: ["apps/payments/ledger", "marta"], number: 3),
                     Self.item(.pull, "Unrelated", keywords: ["oss/lib", "luis"], number: 4)]
        let sections = CommandPaletteSections.build(items: items, query: "marta retry")
        #expect(sections.flatMap(\.rows).map(\.item.label) == ["Retry on timeout"])
        #expect(sections[0].rows[0].match?.indices == [0, 1, 2, 3, 4])
    }

    @Test("Pinned rows lead the Pull requests group, which goes first; a scope other than All or Pull requests drops them")
    func pinned() {
        let items = [Self.item(.command, "Fetch all"), Self.item(.pull, "Bump deps", keywords: ["octo/app"], number: 8),
                     Self.item(.branch, "feature/x")]
        let link = Self.item(.pull, "Open pull request #7")
        let query = "https://github.com/octo/app/pull/7"

        let all = CommandPaletteSections.build(items: items, query: query, pinned: [link])
        #expect(all.first?.kind == .pull)
        #expect(all.first?.rows.first?.item.id == link.id)
        #expect(all.filter { $0.kind == .pull }.count == 1)

        let pulls = CommandPaletteSections.build(items: items, query: query, scope: .only(.pull), pinned: [link])
        #expect(pulls.map(\.kind) == [.pull])
        #expect(pulls[0].rows.map(\.item.id) == [link.id])

        let branches = CommandPaletteSections.build(items: items, query: query, scope: .only(.branch), pinned: [link])
        #expect(branches.allSatisfy { $0.kind == .branch })
        #expect(!branches.flatMap(\.rows).contains { $0.item.id == link.id })
    }

    @Test("Pinned rows share the group with the pull requests that match, ahead of them, and the other groups follow")
    func pinnedBeforeMatches() {
        let items = [Self.item(.branch, "ledger-fix"), Self.item(.pull, "Fix the ledger", keywords: ["octo/app"], number: 8),
                     Self.item(.command, "Ledger report")]
        let link = Self.item(.pull, "Open pull request #7")
        let sections = CommandPaletteSections.build(items: items, query: "ledger", pinned: [link])
        #expect(sections.map(\.kind) == [.pull, .command, .branch])
        #expect(sections[0].rows.map(\.item.label) == ["Open pull request #7", "Fix the ledger"])
        #expect(sections[0].rows.first?.match == nil)
    }

    @Test("Pinned rows show without a query too")
    func pinnedWithoutQuery() {
        let link = Self.item(.pull, "Open pull request #7")
        let sections = CommandPaletteSections.build(items: [Self.item(.command, "Fetch all")], query: "", pinned: [link])
        #expect(sections.map(\.kind) == [.pull, .command])
    }

    @Test("⌘↵ keeps the palette open except for actions that open a panel or sheet")
    func presentsUI() {
        #expect(PaletteAction.openRepository.presentsUI)
        #expect(PaletteAction.cloneRepository.presentsUI)
        #expect(!PaletteAction.fetch.presentsUI)
        #expect(!PaletteAction.selectSection(.history).presentsUI)
    }
}
