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
    /// in the Pull requests and Repositories scopes, what a host search finds.
    static func build(items: [CommandPaletteItem], query: String, scope: CommandPaletteScope = .all,
                      pinned: [CommandPaletteItem] = [], trailing: [CommandPaletteItem] = []) -> [Section] {
        let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        let scopeKinds: [CommandPaletteItem.Kind] = switch scope {
        case .all: CommandPaletteItem.Kind.displayOrder
        case .only(let kind): [kind]
        }
        let pinnedRows = scopeKinds.contains(.pull) ? pinned.map { Row(item: $0, match: nil) } : []
        let kinds = pinnedRows.isEmpty ? scopeKinds : [.pull] + scopeKinds.filter { $0 != .pull }
        let remote = scopeKinds.contains(.pull) || scopeKinds.contains(.repo) ? trailing : []
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
