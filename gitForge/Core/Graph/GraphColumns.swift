import Foundation

/// Stage 3 of the layout: the column of every line and merge track.
///
/// Two lines never share a column on any row, ends included (§3.4.4). Each one
/// occupies the closed row interval it is drawn over, so a line that ends on a
/// row and one that starts on it end up in different columns.
nonisolated struct GraphColumns: Sendable {
    /// Column of each entry of `GraphLines.lines`.
    var columnOfLine: [Int]
    /// Column of each entry of `GraphConnections.tracks`.
    var columnOfTrack: [Int]
    /// Columns in use, at least 1.
    var count: Int

    /// Assigns columns in two passes, so that nothing already placed ever moves
    /// when more history is loaded (§3.9):
    /// 1. **Reserved** lines, from row 0 down to where they end: HEAD, then the
    ///    trunks (rank 0) and develop (rank 1). Only when the line's first row is
    ///    in the first page; a later one is placed like any other line.
    /// 2. **The rest**, by first row, a line before a track starting on the same
    ///    row. A line takes the leftmost free column. A track whose target line
    ///    already has a column goes to the free column nearest to the span between
    ///    its merge and its parent; any other track (the target has not started
    ///    yet, or the parent is on a later page or unloaded) goes to the nearest
    ///    free column right of its merge.
    static func assign(_ input: GraphInput, lines: GraphLines, connections: GraphConnections) -> GraphColumns {
        var occupancy = ColumnOccupancy()
        var columnOfLine = Array(repeating: -1, count: lines.lines.count)
        var columnOfTrack = Array(repeating: -1, count: connections.tracks.count)

        for index in reservedLines(input, lines.lines) {
            columnOfLine[index] = occupancy.occupy(leftmostFreeAfter: -1, from: 0, to: lines.lines[index].bottom)
        }

        for item in remainingItems(lines.lines, connections.tracks, placed: columnOfLine) {
            if item.isTrack {
                let track = connections.tracks[item.index]
                let end = track.parentRow ?? Int.max
                // A track starts on a row of the line it leaves, and that line starts no later.
                let mergeColumn = columnOfLine[track.fromLine]
                if !track.sticky, let toLine = track.toLine, columnOfLine[toLine] >= 0 {
                    columnOfTrack[item.index] = occupancy.occupy(nearestFrom: mergeColumn, to: columnOfLine[toLine],
                                                                 start: item.start, end: end)
                } else {
                    columnOfTrack[item.index] = occupancy.occupy(leftmostFreeAfter: mergeColumn, from: item.start, to: end)
                }
            } else {
                columnOfLine[item.index] = occupancy.occupy(leftmostFreeAfter: -1, from: item.start,
                                                            to: lines.lines[item.index].bottom)
            }
        }
        return GraphColumns(columnOfLine: columnOfLine, columnOfTrack: columnOfTrack, count: max(1, occupancy.count))
    }
}

// MARK: - Order

private nonisolated extension GraphColumns {
    /// A line or a track still waiting for its column.
    nonisolated struct Item {
        let start: Int
        let isTrack: Bool
        let index: Int

        var sortKey: (Int, Int, Int) { (start, isTrack ? 1 : 0, index) }
    }

    /// Indices of the lines that claim their column up front, in claim order:
    /// HEAD's line, then rank 0, then rank 1, each rank by first row.
    static func reservedLines(_ input: GraphInput, _ lines: [GraphLine]) -> [Int] {
        let firstPageEnd = input.firstPageEnd
        let headOwner = input.headBranch.map(GraphOwner.branch) ?? .head
        var head: [Int] = []
        var trunks: [(rank: Int, top: Int, index: Int)] = []
        for (index, line) in lines.enumerated() {
            guard let firstRow = line.rows.first, firstRow < firstPageEnd else { continue }
            if line.owner == headOwner {
                head.append(index)
            } else if case .branch(let name) = line.owner, GraphPriority.rank(name) <= 1 {
                trunks.append((GraphPriority.rank(name), line.top, index))
            }
        }
        return head + trunks.sorted { ($0.rank, $0.top, $0.index) < ($1.rank, $1.top, $1.index) }.map(\.index)
    }

    /// Every line not yet placed and every track, in assignment order.
    static func remainingItems(_ lines: [GraphLine], _ tracks: [GraphTrack], placed: [Int]) -> [Item] {
        var items: [Item] = []
        items.reserveCapacity(lines.count + tracks.count)
        for (index, line) in lines.enumerated() where placed[index] < 0 {
            items.append(Item(start: line.top, isTrack: false, index: index))
        }
        for (index, track) in tracks.enumerated() {
            items.append(Item(start: track.mergeRow, isTrack: true, index: index))
        }
        return items.sorted { $0.sortKey < $1.sortKey }
    }
}

// MARK: - Occupancy

/// The rows each column is taken on, as disjoint closed intervals sorted by
/// start. Checking an interval is a binary search, so placing never scans rows.
private nonisolated struct ColumnOccupancy {
    private struct Interval {
        let start: Int
        let end: Int
    }

    private var columns: [[Interval]] = []

    var count: Int { columns.count }

    /// Places `[start, end]` in the leftmost free column right of `column`
    /// (`-1` for any) and returns it. Falls back to a new column.
    mutating func occupy(leftmostFreeAfter column: Int, from start: Int, to end: Int) -> Int {
        var candidate = column + 1
        while !isFree(candidate, start, end) { candidate += 1 }
        take(candidate, start, end)
        return candidate
    }

    /// Places `[start, end]` in the free column nearest to the span between
    /// `mergeColumn` and `parentColumn`, which may be a new one. The order is:
    /// distance outside the span, then distance to the parent's column, then
    /// the leftmost.
    mutating func occupy(nearestFrom mergeColumn: Int, to parentColumn: Int, start: Int, end: Int) -> Int {
        let low = min(mergeColumn, parentColumn)
        let high = max(mergeColumn, parentColumn)
        var best = columns.count
        var bestKey = (max(low - best, 0) + max(best - high, 0), abs(best - parentColumn), best)
        for candidate in columns.indices where isFree(candidate, start, end) {
            let key = (max(low - candidate, 0) + max(candidate - high, 0), abs(candidate - parentColumn), candidate)
            if key < bestKey {
                best = candidate
                bestKey = key
            }
        }
        take(best, start, end)
        return best
    }

    private func isFree(_ column: Int, _ start: Int, _ end: Int) -> Bool {
        guard column < columns.count else { return true }
        let intervals = columns[column]
        let next = firstIndex(in: intervals, endingAtOrAfter: start)
        return next == intervals.count || intervals[next].start > end
    }

    private mutating func take(_ column: Int, _ start: Int, _ end: Int) {
        if column == columns.count { columns.append([]) }
        let position = firstIndex(in: columns[column], endingAtOrAfter: start)
        columns[column].insert(Interval(start: start, end: end), at: position)
    }

    /// Index of the first interval that ends at or after `row`, or `count`.
    /// Disjoint intervals sorted by start are sorted by end too.
    private func firstIndex(in intervals: [Interval], endingAtOrAfter row: Int) -> Int {
        var low = 0
        var high = intervals.count
        while low < high {
            let middle = low + (high - low) / 2
            if intervals[middle].end >= row { high = middle } else { low = middle + 1 }
        }
        return low
    }
}
