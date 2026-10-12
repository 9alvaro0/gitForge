import Foundation

/// ⌘K results grouped by kind (Actions, Repositories, Branches, Commits,
/// Files), each group ranked by its fuzzy score.
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

    /// Rows per group without a query (actions are all shown) and with one.
    static let browseLimit = 5
    static let searchLimit = 6

    static func build(items: [CommandPaletteItem], query: String) -> [Section] {
        let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        return CommandPaletteItem.Kind.displayOrder.compactMap { kind in
            let ofKind = items.filter { $0.kind == kind }
            let rows: [Row]
            if searching {
                rows = ranked(ofKind, query: query)
            } else {
                let shown = kind == .command ? ofKind : Array(ofKind.prefix(browseLimit))
                rows = shown.map { Row(item: $0, match: nil) }
            }
            return rows.isEmpty ? nil : Section(kind: kind, rows: rows)
        }
    }

    /// Matching items, best score first; ties keep their input order.
    private static func ranked(_ items: [CommandPaletteItem], query: String) -> [Row] {
        var scored: [(offset: Int, row: Row, score: Int)] = []
        for (offset, item) in items.enumerated() {
            guard let match = FuzzyMatcher.match(query, in: item.label) else { continue }
            scored.append((offset, Row(item: item, match: match), match.score))
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.offset < $1.offset }
        return scored.prefix(searchLimit).map(\.row)
    }
}
