import Foundation
import Testing
@testable import gitForge

/// Where ⌘K's selection goes when its rows change under it, the query and
/// the scope unchanged (a host search landing): the same row if it's still
/// listed, else the same place.
@Suite("Command palette — the selection keeps its row")
@MainActor
struct CommandPaletteSelectionTests {
    private static let first = HostingInstance(kind: .gitlab, host: "gitlab.example.test")
    private static let second = HostingInstance(kind: .github, host: "ghe.example.test")

    /// The Search all rows of "retry" on both instances, `first` in `phase`.
    private static func rows(first phase: HostSearchState.Phase?) -> [CommandPaletteSections.Row] {
        let searches = phase.map { [first.id: HostSearchState(query: "retry", phase: $0)] } ?? [:]
        let trailing = CommandPaletteBuilder.searchItems(for: "retry", instances: [first, second],
                                                         searches: searches, followed: [])
        return CommandPaletteSections.build(items: [], query: "retry", trailing: trailing).flatMap(\.rows)
    }

    private static func results() throws -> HostSearchResults {
        let repos = try ["oss/lib", "oss/lib-tools", "apps/payments/backend/ledger"].map { path in
            FoundRepo(host: try #require(RemoteHost.make(fullName: path, on: first)), instanceId: first.id,
                      cloneURL: "https://gitlab.example.test/\(path).git")
        }
        return HostSearchResults(repos: repos)
    }

    @Test("The selected search row of another host stays selected when results land before it")
    func keepsTheRow() throws {
        let before = Self.rows(first: .searching)
        #expect(before.map(\.item.label) == ["Searching gitlab.example.test…", "Search all of ghe.example.test"])
        let selected = before[1].item

        let after = Self.rows(first: .found(try Self.results()))

        let index = CommandPaletteSections.selection(keeping: selected, in: after, fallback: 1)
        #expect(index == 3)
        #expect(after[index].item.label == "Search all of ghe.example.test")
        #expect(after[index].item.action == .searchHost(instanceId: Self.second.id, query: "retry"))
    }

    @Test("A selected row that's gone leaves the selection at the same place, within the rows")
    func sameIndexWhenGone() throws {
        let before = Self.rows(first: .searching)
        let searching = before[0].item

        let found = Self.rows(first: .found(try Self.results()))
        #expect(CommandPaletteSections.selection(keeping: searching, in: found, fallback: 0) == 0)

        let nothing = Self.rows(first: .found(HostSearchResults()))
        #expect(CommandPaletteSections.selection(keeping: searching, in: nothing, fallback: 5) == nothing.count - 1)
        #expect(CommandPaletteSections.selection(keeping: nil, in: nothing, fallback: 1) == 1)
        #expect(CommandPaletteSections.selection(keeping: nil, in: nothing, fallback: -2) == 0)
    }

    @Test("No rows, no selection to keep: the first place")
    func emptyRows() {
        let item = CommandPaletteItem(kind: .remote, label: "Search all of gitlab.example.test", hint: nil, action: .noop)
        #expect(CommandPaletteSections.selection(keeping: item, in: [], fallback: 4) == 0)
        #expect(CommandPaletteSections.selection(keeping: nil, in: [], fallback: 0) == 0)
    }
}
