import Foundation

// SCRATCH prototype for G5: never merged as is.

/// Where the columns a row draws sat before HEAD changed: the old column of each
/// new column at the centre of the row above, the row's own centre and the row below.
nonisolated struct GraphRowMotion: Sendable, Hashable {
    let above: [Int16]
    let center: [Int16]
    let below: [Int16]
}

nonisolated enum GraphMotionBuilder {
    /// Rows of `new` (same commits as `old`) whose columns move, by sha.
    static func motion(from old: GraphInput, to new: GraphInput, newLayout: GraphLayout) -> [String: GraphRowMotion] {
        let count = new.commits.count
        guard count > 0, old.commits.count == count else { return [:] }
        for row in 0..<count where old.commits[row].sha != new.commits[row].sha { return [:] }
        let rowOf = new.rowIndex()
        let before = Stages(old, rowOf: rowOf)
        let after = Stages(new, rowOf: rowOf)
        let verticalBefore = before.verticalColumns()
        let width = max(newLayout.columnCount, 1)

        // Old column of every new column at every centre, the bottom edge included.
        var oldOf = [[Int16]](repeating: (0..<width).map { Int16($0) }, count: count + 1)
        for row in 0..<count {
            let column = after.nodeColumn(row)
            if column < width { oldOf[row][column] = Int16(before.nodeColumn(row)) }
        }
        after.forEachPassing { column, first, last, key in
            guard column < width, let oldColumn = verticalBefore[key] else { return }
            for centre in first...min(last, count) { oldOf[centre][column] = Int16(oldColumn) }
        }

        let identity = (0..<width).map { Int16($0) }
        var rows: [String: GraphRowMotion] = [:]
        for row in 0..<count {
            let used = newLayout.rows[row].width
            let above = row > 0 ? Array(oldOf[row - 1].prefix(used)) : Array(identity.prefix(used))
            let center = Array(oldOf[row].prefix(used))
            let below = Array(oldOf[row + 1].prefix(used))
            let still = Array(identity.prefix(used))
            guard above != still || center != still || below != still else { continue }
            rows[new.commits[row].sha] = GraphRowMotion(above: above, center: center, below: below)
        }
        return rows
    }

    /// Edge between a child row and a parent row; an unloaded parent is a negative ordinal.
    static func key(_ child: Int, _ parent: Int) -> Int64 {
        (Int64(child) << 32) | Int64(UInt32(bitPattern: Int32(parent)))
    }

    nonisolated struct Stages {
        let lines: GraphLines
        let connections: GraphConnections
        let columns: GraphColumns

        init(_ input: GraphInput, rowOf: [String: Int]) {
            var lines = GraphLines.build(input, rowOf: rowOf)
            connections = GraphConnections.build(input, rowOf: rowOf, lines: &lines)
            columns = GraphColumns.assign(input, lines: lines, connections: connections)
            self.lines = lines
        }

        func nodeColumn(_ row: Int) -> Int {
            columns.columnOfLine[lines.lineOfRow[row]]
        }

        /// Every edge's column between its child and its parent.
        func verticalColumns() -> [Int64: Int] {
            var result: [Int64: Int] = [:]
            forEachPassing { column, _, _, key in result[key] = column }
            return result
        }

        /// Each edge that runs straight down a column past some row centres:
        /// the column, the first and last centre it passes, and the edge.
        func forEachPassing(_ body: (_ column: Int, _ first: Int, _ last: Int, _ key: Int64) -> Void) {
            let end = lines.lineOfRow.count
            // Joins first: one that fuses with a line already passing shares its column,
            // and the line's own edge is the one to follow there.
            for join in connections.joins where join.parentRow > join.mergeRow + 1 {
                body(columns.columnOfLine[join.toLine], join.mergeRow + 1, join.parentRow - 1,
                     GraphMotionBuilder.key(join.mergeRow, join.parentRow))
            }
            for (index, line) in lines.lines.enumerated() {
                let column = columns.columnOfLine[index]
                for (upper, lower) in zip(line.rows, line.rows.dropFirst()) where lower > upper + 1 {
                    body(column, upper + 1, lower - 1, GraphMotionBuilder.key(upper, lower))
                }
                guard let last = line.rows.last else { continue }
                if let fork = line.forkRow {
                    if fork > last + 1 { body(column, last + 1, fork - 1, GraphMotionBuilder.key(last, fork)) }
                } else if line.continuesPastEnd {
                    body(column, last + 1, end, GraphMotionBuilder.key(last, -1))
                }
            }
            var unloaded: [Int: Int] = [:]
            for (index, track) in connections.tracks.enumerated() {
                let column = columns.columnOfTrack[index]
                if let parent = track.parentRow {
                    guard parent > track.mergeRow + 1 else { continue }
                    body(column, track.mergeRow + 1, parent - 1, GraphMotionBuilder.key(track.mergeRow, parent))
                } else {
                    let ordinal = unloaded[track.mergeRow, default: 0]
                    unloaded[track.mergeRow] = ordinal + 1
                    body(column, track.mergeRow + 1, end, GraphMotionBuilder.key(track.mergeRow, -2 - ordinal))
                }
            }
        }
    }
}

/// The animation in flight: every moving row's motion and when it started.
nonisolated struct GraphMotionState: Sendable, Equatable {
    let id: UInt64
    let start: Date
    let rows: [String: GraphRowMotion]

    static let duration: TimeInterval = 0.3
}
