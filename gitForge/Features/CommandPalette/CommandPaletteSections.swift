import Foundation

/// ⌘K results grouped by kind (Actions, Repositories, Pull requests,
/// Branches, Commits, Files), each group ranked by its match score, and
/// Search all last, as its rows come.
enum CommandPaletteSections {
    struct Row: Identifiable, Equatable {
        let item: CommandPaletteItem
        let match: FuzzyMatch?
        var id: UUID { item.id }
    }

    struct Section: Identifiable, Equatable {
        let kind: CommandPaletteItem.Kind
        let rows: [Row]
        var id: CommandPaletteItem.Kind { kind }
    }

    /// Rows per group in All, without a query (actions are all shown) and
    /// with one; and in a single-group scope, either way.
    static let browseLimit = 5
    static let searchLimit = 6
    static let scopedLimit = 50

    /// `pinned` rows (a pasted pull request link's) lead the Pull requests
    /// group, which then goes first. They show in All and in the Pull requests
    /// scope, whatever the query, and are not counted against the group's limit.
    ///
    /// `trailing` rows ("Search all of <host>" and what it found) are the last
    /// group, Search all, as given: not ranked, not cut. They show in All and
    /// in the Pull requests and Repositories scopes, what a host search finds,
    /// unless there are `pinned` rows, in any scope: a query that is a link
    /// isn't text to search a host for (R3 Ruling Y).
    static func build(items: [CommandPaletteItem], query: String, scope: CommandPaletteScope = .all,
                      pinned: [CommandPaletteItem] = [], trailing: [CommandPaletteItem] = []) -> [Section] {
        let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        let scopeKinds: [CommandPaletteItem.Kind] = switch scope {
        case .all: CommandPaletteItem.Kind.displayOrder
        case .only(let kind): [kind]
        }
        let pinnedRows = scopeKinds.contains(.pull) ? pinned.map { Row(item: $0, match: nil) } : []
        let kinds = pinnedRows.isEmpty ? scopeKinds : [.pull] + scopeKinds.filter { $0 != .pull }
        let remote = pinned.isEmpty && (scopeKinds.contains(.pull) || scopeKinds.contains(.repo)) ? trailing : []
        let remoteSection = remote.isEmpty ? [] : [Section(kind: .remote, rows: remote.map { Row(item: $0, match: nil) })]
        return kinds.compactMap { kind in
            let ofKind = items.filter { $0.kind == kind }
            let found: [Row]
            if searching {
                found = ranked(ofKind, query: query, limit: scope == .all ? searchLimit : scopedLimit)
            } else {
                let limit = scope == .all && kind != .command ? browseLimit : scopedLimit
                found = ofKind.prefix(limit).map { Row(item: $0, match: nil) }
            }
            let rows = kind == .pull ? pinnedRows + found : found
            return rows.isEmpty ? nil : Section(kind: kind, rows: rows)
        } + remoteSection
    }

    /// The selected row's index once `rows` changed under it, the query and
    /// the scope unchanged (a host search landing): the row of `item`, by
    /// its action and label (a rebuilt row is a new item), if it's still
    /// listed; else `fallback`, the index it had, within the rows.
    static func selection(keeping item: CommandPaletteItem?, in rows: [Row], fallback: Int) -> Int {
        guard !rows.isEmpty else { return 0 }
        if let item, let index = rows.firstIndex(where: { $0.item.action == item.action && $0.item.label == item.label }) {
            return index
        }
        return min(max(fallback, 0), rows.count - 1)
    }

    /// One change of the rows under the selection, the query and the scope
    /// unchanged: its place now (`selection(keeping:in:fallback:)`) and what
    /// it keeps for the next change, that place and the row now at it. A row
    /// that's gone hands the selection to the one in its place, which a later
    /// change then follows. With no rows, `item` is kept for when they're back.
    static func follow(_ item: CommandPaletteItem?, at index: Int,
                       in rows: [Row]) -> (index: Int, item: CommandPaletteItem?) {
        let now = selection(keeping: item, in: rows, fallback: index)
        return (now, rows[safe: now]?.item ?? item)
    }

    /// Matching items, best score first; ties keep their input order.
    private static func ranked(_ items: [CommandPaletteItem], query: String, limit: Int) -> [Row] {
        var scored: [(offset: Int, row: Row, score: Int)] = []
        for (offset, item) in items.enumerated() {
            guard let match = PaletteSearch.match(query, label: item.label, keywords: item.keywords, number: item.number)
            else { continue }
            scored.append((offset, Row(item: item, match: match), match.score))
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.offset < $1.offset }
        return scored.prefix(limit).map(\.row)
    }
}
