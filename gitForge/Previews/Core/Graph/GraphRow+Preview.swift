import Foundation

extension Array where Element == GraphRow {
    /// Five consecutive rows for graph previews, so the halves meet across
    /// the row boundaries:
    /// 0. HEAD's tip, a straight line down column 0.
    /// 1. A stash in column 1; its dashed side step curves into the merge.
    /// 2. A merge on HEAD's line; its second parent's track curves right.
    /// 3. The feature commit in column 1 while HEAD's line passes straight.
    /// 4. The commit the feature grew from: the S curves back left into it.
    static var previewSamples: [GraphRow] {
        let head = GraphStep(from: 0, to: 0, color: .head, stroke: .solid)
        let stash = GraphStep(from: 1, to: 0, color: .stash, stroke: .stash)
        let out = GraphStep(from: 0, to: 1, color: .pool(0), stroke: .solid)
        let back = GraphStep(from: 1, to: 0, color: .pool(0), stroke: .solid)
        func node(_ column: Int, _ kind: GraphNode.Kind, _ color: GraphColorRole) -> GraphNode {
            GraphNode(column: column, kind: kind, color: color, isGhost: false)
        }
        return [
            GraphRow(node: node(0, .commit, .head), stepsAbove: [], stepsBelow: [head], width: 1),
            GraphRow(node: node(1, .stash, .stash), stepsAbove: [head], stepsBelow: [head, stash], width: 2),
            GraphRow(node: node(0, .merge, .head), stepsAbove: [head, stash], stepsBelow: [head, out], width: 2),
            GraphRow(node: node(1, .commit, .pool(0)), stepsAbove: [head, out], stepsBelow: [head, back], width: 2),
            GraphRow(node: node(0, .commit, .head), stepsAbove: [head, back], stepsBelow: [head], width: 2),
        ]
    }
}
