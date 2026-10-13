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

    /// Rows per group in All, without a query (actions are all shown) and
    /// with one; and in a single-group scope, either way.
    static let browseLimit = 5
    static let searchLimit = 6
    static let scopedLimit = 50

    static func build(items: [CommandPaletteItem], query: String, scope: CommandPaletteScope = .all) -> [Section] {
        let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        let kinds: [CommandPaletteItem.Kind]
        switch scope {
        case .all: kinds = CommandPaletteItem.Kind.displayOrder
        case .only(let kind): kinds = [kind]
        }
        return kinds.compactMap { kind in
            let ofKind = items.filter { $0.kind == kind }
            let rows: [Row]
            if searching {
                rows = ranked(ofKind, query: query, limit: scope == .all ? searchLimit : scopedLimit)
            } else {
                let limit = scope == .all && kind != .command ? browseLimit : scopedLimit
                rows = ofKind.prefix(limit).map { Row(item: $0, match: nil) }
            }
            return rows.isEmpty ? nil : Section(kind: kind, rows: rows)
        }
    }

    /// Matching items, best score first; ties keep their input order.
    private static func ranked(_ items: [CommandPaletteItem], query: String, limit: Int) -> [Row] {
        var scored: [(offset: Int, row: Row, score: Int)] = []
        for (offset, item) in items.enumerated() {
            guard let match = FuzzyMatcher.match(query, in: item.label) else { continue }
            scored.append((offset, Row(item: item, match: match), match.score))
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.offset < $1.offset }
        return scored.prefix(limit).map(\.row)
    }
}
