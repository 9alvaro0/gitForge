import Foundation

/// A merge whose extra parent joins the parent's line directly.
nonisolated struct GraphJoin: Sendable, Equatable {
    let mergeRow: Int
    let parentRow: Int
    let fromLine: Int
    let toLine: Int
}

/// A merge whose extra parent needs a column of its own.
nonisolated struct GraphTrack: Sendable, Equatable {
    let mergeRow: Int
    let parentRow: Int?      // nil when the parent isn't loaded
    let fromLine: Int
    let toLine: Int?         // nil when the parent isn't loaded
    let sticky: Bool         // parent outside the merge's page, or not loaded
}

/// Stage 2 of the layout: how each extra merge parent reaches its line.
nonisolated struct GraphConnections: Sendable {
    var joins: [GraphJoin]
    var tracks: [GraphTrack]

    /// Fills joins/tracks and raises `lines.lines[i].top` for joined tips.
    ///
    /// Merges are visited top to bottom, and every parent after the first is
    /// connected on its own (§3.3):
    /// - **Sticky track** when the parent is not loaded, or sits past the end of
    ///   the merge's page. Loading more history never turns it into a join (§3.9).
    /// - **Join** when the parent's line is not the merge's and none of its
    ///   commits lies strictly between the two. If the parent is that line's
    ///   tip, the line is lengthened up to the merge.
    /// - **Track** otherwise: merging an ancestor of its own line, or skipping
    ///   over commits of the parent's line. Also a merge of HEAD's tip from above
    ///   while the layout draws the connector (§3.5): lengthening HEAD's line would
    ///   cover the connector in column 0, so the merge enters the tip from the side.
    ///
    /// A stash's parents (index, untracked files) are not merges. A parent that
    /// repeats an earlier one of the same commit adds no connection.
    static func build(_ input: GraphInput, rowOf: [String: Int], lines: inout GraphLines) -> GraphConnections {
        var connections = GraphConnections(joins: [], tracks: [])
        let headOwner = input.headBranch.map(GraphOwner.branch) ?? .head
        let headLine = input.drawsUncommittedConnector ? lines.lines.firstIndex { $0.owner == headOwner } : nil
        for (mergeRow, commit) in input.commits.enumerated() {
            guard commit.parentShas.count > 1, !input.stashShas.contains(commit.sha) else { continue }
            let fromLine = lines.lineOfRow[mergeRow]
            let pageEnd = input.pageEnd(containing: mergeRow)
            var seen: Set<String> = [commit.parentShas[0]]
            for parent in commit.parentShas.dropFirst() where seen.insert(parent).inserted {
                guard let parentRow = rowOf[parent] else {
                    connections.tracks.append(GraphTrack(mergeRow: mergeRow, parentRow: nil, fromLine: fromLine,
                                                         toLine: nil, sticky: true))
                    continue
                }
                let toLine = lines.lineOfRow[parentRow]
                let entersHeadTip = toLine == headLine && lines.lines[toLine].rows.first == parentRow
                if parentRow >= pageEnd {
                    connections.tracks.append(GraphTrack(mergeRow: mergeRow, parentRow: parentRow, fromLine: fromLine,
                                                         toLine: toLine, sticky: true))
                } else if toLine != fromLine, !entersHeadTip,
                          !lines.lines[toLine].rows.containsValue(strictlyBetween: mergeRow, and: parentRow) {
                    connections.joins.append(GraphJoin(mergeRow: mergeRow, parentRow: parentRow,
                                                       fromLine: fromLine, toLine: toLine))
                    if lines.lines[toLine].rows.first == parentRow, mergeRow < lines.lines[toLine].top {
                        lines.lines[toLine].top = mergeRow
                    }
                } else {
                    connections.tracks.append(GraphTrack(mergeRow: mergeRow, parentRow: parentRow, fromLine: fromLine,
                                                         toLine: toLine, sticky: false))
                }
            }
        }
        return connections
    }
}

private nonisolated extension Array where Element == Int {
    /// Whether an element lies strictly between `low` and `high`. The array
    /// must be ascending; O(log n).
    func containsValue(strictlyBetween low: Int, and high: Int) -> Bool {
        let next = upperBound(of: low)
        return next < count && self[next] < high
    }
}
