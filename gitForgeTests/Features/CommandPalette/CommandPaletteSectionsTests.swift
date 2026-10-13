import Foundation
import Testing
@testable import gitForge

@Suite("Command palette sections")
@MainActor
struct CommandPaletteSectionsTests {

    private static func item(_ kind: CommandPaletteItem.Kind, _ label: String) -> CommandPaletteItem {
        CommandPaletteItem(kind: kind, label: label, hint: nil, action: .noop)
    }

    @Test("Groups go Actions, Repositories, Branches, Commits, Files; empty ones are left out")
    func order() {
        let items = [Self.item(.file, "a.swift"), Self.item(.commit, "Fix"), Self.item(.command, "Fetch all"),
                     Self.item(.repo, "me/app")]
        let sections = CommandPaletteSections.build(items: items, query: "")
        #expect(sections.map(\.kind) == [.command, .repo, .commit, .file])
        #expect(sections.map(\.kind.title) == ["Actions", "Repositories", "Commits", "Files"])
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
        #expect(seen == ["Actions", "Repositories", "Branches", "Commits", "Files", "All"])
        #expect(CommandPaletteScope.all.previous() == .only(.file))
        #expect(CommandPaletteScope.only(.command).previous() == .all)
    }

    @Test("⌘↵ keeps the palette open except for actions that open a panel or sheet")
    func presentsUI() {
        #expect(PaletteAction.openRepository.presentsUI)
        #expect(PaletteAction.cloneRepository.presentsUI)
        #expect(!PaletteAction.fetch.presentsUI)
        #expect(!PaletteAction.selectSection(.history).presentsUI)
    }
}
