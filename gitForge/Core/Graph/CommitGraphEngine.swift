import Foundation

/// The commit graph layout (§3 to §5.1): which column each commit sits in and
/// which steps cross each row.
nonisolated enum CommitGraphEngine {
    /// Chains the stages (lines, merge connections, columns, ghosts, colours)
    /// and emits every row's node and steps.
    ///
    /// A step lives on a boundary `b`, between rows `b` and `b + 1`; the one
    /// below the last row runs to the bottom edge. Each boundary's list goes to
    /// `rows[b].stepsBelow` and `rows[b + 1].stepsAbove` alike, sorted by
    /// `(from, to)`. The connector from the Uncommitted changes row (§3.5) also
    /// crosses the top edge, so it is the first row's `stepsAbove`.
    static func layout(_ input: GraphInput) -> GraphLayout {
        let count = input.commits.count
        guard count > 0 else { return .empty }

        let rowOf = input.rowIndex()
        var lines = GraphLines.build(input, rowOf: rowOf)
        let connections = GraphConnections.build(input, rowOf: rowOf, lines: &lines)
        let columns = GraphColumns.assign(input, lines: lines, connections: connections)
        let ghostRows = GraphReachability.ghostRows(input, rowOf: rowOf)
        let coloring = GraphColoring.assign(input, lines: lines, columns: columns)
        let roleOfRow = lines.colorOwnerOfRow.map(coloring.role)

        // The connector runs down into HEAD's row, or to the bottom edge while HEAD's commit is not loaded.
        let connector: GraphStep? = input.drawsUncommittedConnector ? .uncommitted : nil
        let lastConnectorBoundary: Int? = connector == nil ? nil : (input.headSha.flatMap { rowOf[$0] } ?? count) - 1
        var emitter = StepEmitter(lines: lines, connections: connections, columns: columns, ghostRows: ghostRows,
                                  roleOfRow: roleOfRow, lastConnectorBoundary: lastConnectorBoundary)
        let boundaries = emitter.emit()
        let rightmost = boundaries.map { steps in steps.reduce(0) { max($0, $1.from, $1.to) } }

        var stashRows = Array(repeating: false, count: count)
        for sha in input.stashShas {
            if let row = rowOf[sha] { stashRows[row] = true }
        }

        let topEdge = connector.map { [$0] } ?? []
        var rows: [GraphRow] = []
        rows.reserveCapacity(count)
        for (row, commit) in input.commits.enumerated() {
            let kind: GraphNode.Kind = stashRows[row] ? .stash : commit.parentShas.count > 1 ? .merge : .commit
            let node = GraphNode(column: columns.columnOfLine[lines.lineOfRow[row]], kind: kind,
                                 color: roleOfRow[row], isGhost: ghostRows[row])
            let rightmostAbove = row > 0 ? rightmost[row - 1] : 0
            rows.append(GraphRow(node: node, stepsAbove: row > 0 ? boundaries[row - 1] : topEdge,
                                 stepsBelow: boundaries[row],
                                 width: 1 + max(node.column, rightmostAbove, rightmost[row])))
        }
        return GraphLayout(rows: rows, columnCount: columns.count, uncommitted: connector)
    }
}

// MARK: - Steps

/// Writes the steps of every line, join and track on the boundaries they cross,
/// and the connector from the Uncommitted changes row.
///
/// - **Colour** is the role of the commit that owns the segment: the commit
///   above it on a line, the parent for a join or a track (`.neutral` when the
///   track is sticky, so loading its parent never recolours it). The connector
///   is always `.head`, whoever owns HEAD's commit (§3.5).
/// - **Stroke** is `.uncommitted` for the connector and `.stash` on a stash's
///   line; otherwise `.ghost` when the child commit of the edge is a ghost (the
///   merge, for joins, tracks and the stretch a join adds above a line's tip);
///   otherwise `.solid`.
private nonisolated struct StepEmitter {
    let lines: GraphLines
    let connections: GraphConnections
    let columns: GraphColumns
    let ghostRows: [Bool]
    /// Colour role of each row's colour owner, looked up once per row.
    let roleOfRow: [GraphColorRole]
    /// The last boundary the connector crosses: the one above HEAD's row (-1 when
    /// HEAD is the first row), or the bottom edge while HEAD's commit is not loaded.
    /// Nil without the connector.
    let lastConnectorBoundary: Int?
    /// Steps of boundary `b`, between rows `b` and `b + 1`. The last one is the bottom edge.
    private var boundaries: [[GraphStep]]

    init(lines: GraphLines, connections: GraphConnections, columns: GraphColumns,
         ghostRows: [Bool], roleOfRow: [GraphColorRole], lastConnectorBoundary: Int?) {
        self.lines = lines
        self.connections = connections
        self.columns = columns
        self.ghostRows = ghostRows
        self.roleOfRow = roleOfRow
        self.lastConnectorBoundary = lastConnectorBoundary
        boundaries = Array(repeating: [], count: ghostRows.count)
    }

    private var lastBoundary: Int { boundaries.count - 1 }

    /// Every boundary's steps, sorted by `(from, to)`.
    ///
    /// Each line, join and track is visited once and writes one step per
    /// boundary it crosses. They are visited by the column their steps leave
    /// from, left to right, so every boundary fills in ascending `from`. Only
    /// the steps leaving a node (its line, joins and tracks) can come out of
    /// order, so the final sort has next to nothing to move. The connector goes
    /// first: it is the only step in column 0 on the boundaries it crosses.
    mutating func emit() -> [[GraphStep]] {
        emitConnector()
        let columnCount = columns.count
        var linesFrom = Array(repeating: [Int](), count: columnCount)
        for index in lines.lines.indices {
            linesFrom[columns.columnOfLine[index]].append(index)
        }
        var joinsFrom = Array(repeating: [Int](), count: columnCount)
        for (index, join) in connections.joins.enumerated() {
            joinsFrom[columns.columnOfLine[join.fromLine]].append(index)
        }
        var tracksFrom = Array(repeating: [Int](), count: columnCount)
        var trackStartsFrom = Array(repeating: [Int](), count: columnCount)
        for (index, track) in connections.tracks.enumerated() {
            tracksFrom[columns.columnOfTrack[index]].append(index)
            trackStartsFrom[columns.columnOfLine[track.fromLine]].append(index)
        }

        for column in 0..<columnCount {
            for index in linesFrom[column] { emitLine(index) }
            for index in tracksFrom[column] { emitTrackBody(index) }
            for index in joinsFrom[column] { emitJoin(index) }
            for index in trackStartsFrom[column] { emitTrackStart(index) }
        }
        for index in boundaries.indices where boundaries[index].count > 1 {
            boundaries[index].sort { $0.from < $1.from || ($0.from == $1.from && $0.to < $1.to) }
        }
        return boundaries
    }

    // MARK: Connector

    /// The connector from the Uncommitted changes row (§3.5): straight down
    /// column 0 from the top edge, on every boundary above HEAD's row.
    private mutating func emitConnector() {
        guard let lastConnectorBoundary else { return }
        for boundary in 0..<(lastConnectorBoundary + 1) {
            boundaries[boundary].append(.uncommitted)
        }
    }

    // MARK: Lines

    /// A drawn line, in its column:
    /// - A join that raised its top runs straight from below the merge down to its first row.
    /// - Straight between consecutive rows.
    /// - Born from another line: straight down to the row above the fork, then
    ///   an S into the fork's column.
    /// - Running past the loaded rows: straight to the bottom edge.
    private mutating func emitLine(_ index: Int) {
        let line = lines.lines[index]
        guard let first = line.rows.first, let last = line.rows.last else { return }
        let column = columns.columnOfLine[index]
        let isStash = if case .stash = line.owner { true } else { false }

        if line.top < first {
            straight(column, from: line.top + 1, through: first - 1, color: roleOfRow[first],
                     stroke: stroke(isStash: isStash, childRow: line.top))
        }
        for (upper, lower) in zip(line.rows, line.rows.dropFirst()) {
            straight(column, from: upper, through: lower - 1, color: roleOfRow[upper],
                     stroke: stroke(isStash: isStash, childRow: upper))
        }
        let color = roleOfRow[last]
        let lastStroke = stroke(isStash: isStash, childRow: last)
        if let fork = line.forkRow {
            straight(column, from: last, through: fork - 2, color: color, stroke: lastStroke)
            add(at: fork - 1, from: column, to: nodeColumn(fork), color: color, stroke: lastStroke)
        } else if line.continuesPastEnd {
            straight(column, from: last, through: lastBoundary, color: color, stroke: lastStroke)
        }
    }

    private func stroke(isStash: Bool, childRow: Int) -> GraphStroke {
        isStash ? .stash : ghostRows[childRow] ? .ghost : .solid
    }

    // MARK: Merges

    /// An S from the merge into the parent's line, on the boundary below the merge.
    private mutating func emitJoin(_ index: Int) {
        let join = connections.joins[index]
        add(at: join.mergeRow, from: columns.columnOfLine[join.fromLine], to: columns.columnOfLine[join.toLine],
            color: roleOfRow[join.parentRow], stroke: mergeStroke(join.mergeRow))
    }

    /// The S from the merge into the track's column.
    ///
    /// A track whose parent is the very next row has no row to run down, since
    /// both of its S curves would fall on the same boundary. It becomes a single
    /// S from the merge into the parent. A sticky track is that short when the
    /// merge ends one page and the parent starts the next: only the merge row's
    /// `stepsBelow` changes when that page loads, as with a line that ran past
    /// the end and now forks.
    private mutating func emitTrackStart(_ index: Int) {
        let track = connections.tracks[index]
        let target = directParentRow(track).map(nodeColumn) ?? columns.columnOfTrack[index]
        add(at: track.mergeRow, from: columns.columnOfLine[track.fromLine], to: target,
            color: trackColor(track), stroke: mergeStroke(track.mergeRow))
    }

    /// The rest of a track, in its own column: straight down and an S into the
    /// parent's node from the side, or straight to the bottom edge when the
    /// parent is not loaded.
    private mutating func emitTrackBody(_ index: Int) {
        let track = connections.tracks[index]
        guard directParentRow(track) == nil else { return }
        let column = columns.columnOfTrack[index]
        let color = trackColor(track)
        let stroke = mergeStroke(track.mergeRow)
        guard let parentRow = track.parentRow else {
            straight(column, from: track.mergeRow + 1, through: lastBoundary, color: color, stroke: stroke)
            return
        }
        straight(column, from: track.mergeRow + 1, through: parentRow - 2, color: color, stroke: stroke)
        add(at: parentRow - 1, from: column, to: nodeColumn(parentRow), color: color, stroke: stroke)
    }

    /// The parent's row when it sits right below the merge. Only two tracks can
    /// be that short: a sticky one, and one into HEAD's tip while the layout
    /// draws the connector (§3.5). Any other such parent is either on the
    /// merge's own line, so it is the first parent and adds no connection, or
    /// on another line with nothing in between, which makes a join.
    private func directParentRow(_ track: GraphTrack) -> Int? {
        guard let parentRow = track.parentRow, parentRow == track.mergeRow + 1 else { return nil }
        return parentRow
    }

    private func nodeColumn(_ row: Int) -> Int {
        columns.columnOfLine[lines.lineOfRow[row]]
    }

    private func trackColor(_ track: GraphTrack) -> GraphColorRole {
        guard !track.sticky, let parentRow = track.parentRow else { return .neutral }
        return roleOfRow[parentRow]
    }

    private func mergeStroke(_ mergeRow: Int) -> GraphStroke {
        ghostRows[mergeRow] ? .ghost : .solid
    }

    // MARK: Writing

    /// Straight steps in `column` on boundaries `first...last`; none when `last < first`.
    private mutating func straight(_ column: Int, from first: Int, through last: Int,
                                   color: GraphColorRole, stroke: GraphStroke) {
        guard first <= last else { return }
        let step = GraphStep(from: column, to: column, color: color, stroke: stroke)
        for boundary in first...last {
            boundaries[boundary].append(step)
        }
    }

    private mutating func add(at boundary: Int, from: Int, to: Int, color: GraphColorRole, stroke: GraphStroke) {
        boundaries[boundary].append(GraphStep(from: from, to: to, color: color, stroke: stroke))
    }
}
