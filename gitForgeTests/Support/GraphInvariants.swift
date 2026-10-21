import Foundation
import Testing
@testable import gitForge

/// Structural rules every `GraphLayout` must keep, whatever the history.
enum GraphInvariants {
    /// Records one issue at the caller's location per broken rule.
    static func check(_ layout: GraphLayout, _ input: GraphInput, sourceLocation: SourceLocation = #_sourceLocation) {
        for violation in violations(layout, input) {
            Issue.record(Comment(rawValue: violation), sourceLocation: sourceLocation)
        }
    }

    /// One description per broken rule; empty when the layout is sound.
    static func violations(_ layout: GraphLayout, _ input: GraphInput) -> [String] {
        let rows = layout.rows
        let commits = input.commits
        var violations: [String] = []

        // 1. One row per commit.
        guard rows.count == commits.count else {
            return ["\(rows.count) rows for \(commits.count) commits"]
        }

        for boundary in rows.indices {
            let steps = rows[boundary].stepsBelow
            let isLast = boundary + 1 == rows.count

            // 2. A boundary is shared: the row below draws the same steps from its top edge.
            if !isLast, steps != rows[boundary + 1].stepsAbove {
                violations.append("Boundary \(boundary): stepsBelow \(steps) differ from the next stepsAbove "
                                  + "\(rows[boundary + 1].stepsAbove)")
            }

            // 3. One line per column: away from the nodes, no two steps leave or reach the same column,
            //    except where a merge join fuses with a line that already passes (§3.3). Below the
            //    last row there is no node, so every column reached there must be unique.
            let upperColumn = rows[boundary].node.column
            for column in repeated(steps.map(\.from), except: upperColumn) {
                violations.append("Boundary \(boundary): several steps leave column \(column): \(steps)")
            }
            for column in repeated(steps.map(\.to), except: isLast ? nil : rows[boundary + 1].node.column)
            where isLast || !isFusedJoin(steps.filter { $0.to == column }, column: column, upperColumn: upperColumn) {
                violations.append("Boundary \(boundary): several steps reach column \(column): \(steps)")
            }
        }

        // 4. Continuity: what passes through a row without touching its node goes on below.
        for (index, row) in rows.enumerated().dropFirst() {
            let column = row.node.column
            let arriving = Set(row.stepsAbove.map(\.to)).subtracting([column])
            let leaving = Set(row.stepsBelow.map(\.from)).subtracting([column])
            if arriving != leaving {
                violations.append("Row \(index): columns \(arriving.sorted()) arrive from above but "
                                  + "\(leaving.sorted()) leave below")
            }
        }

        // 5. A node is reached from above exactly when a loaded child has it as a parent.
        //    A stash's index and untracked parents are not edges of the graph.
        let rowOf = input.rowIndex()
        var hasChild = Array(repeating: false, count: commits.count)
        for commit in commits {
            let parents = input.stashShas.contains(commit.sha) ? Array(commit.parentShas.prefix(1)) : commit.parentShas
            for parent in parents {
                if let parentRow = rowOf[parent] { hasChild[parentRow] = true }
            }
        }
        for (index, row) in rows.enumerated() {
            let reached = row.stepsAbove.contains { $0.to == row.node.column }
            if reached != hasChild[index] {
                violations.append("Row \(index) (\(commits[index].sha)): reached from above is \(reached), "
                                  + "has a loaded child is \(hasChild[index])")
            }
        }

        // 6. A node with parents leaves its column towards them.
        for (index, row) in rows.enumerated() where !commits[index].parentShas.isEmpty {
            if !row.stepsBelow.contains(where: { $0.from == row.node.column }) {
                violations.append("Row \(index) (\(commits[index].sha)) has parents but no step leaves column "
                                  + "\(row.node.column): \(row.stepsBelow)")
            }
        }

        for (index, row) in rows.enumerated() {
            // 7. Each boundary is sorted by `(from, to)`.
            let pairs = row.stepsBelow.map { [$0.from, $0.to] }
            if pairs != pairs.sorted(by: { $0.lexicographicallyPrecedes($1) }) {
                violations.append("Boundary \(index) is not sorted by (from, to): \(row.stepsBelow)")
            }

            // 8. The width is one past the rightmost column of the node and its steps.
            let rightmost = (row.stepsAbove + row.stepsBelow).reduce(row.node.column) { max($0, $1.from, $1.to) }
            if row.width != rightmost + 1 {
                violations.append("Row \(index): width \(row.width), but its rightmost column is \(rightmost)")
            }
        }
        return violations
    }

    /// The one shape where several steps may reach a column with no node: a
    /// merge join fusing with a line that already passes (§3.3). That is one
    /// straight step down `column` plus join curves from the node above. A join
    /// always lands on a loaded row, so this never applies below the last row.
    private static func isFusedJoin(_ landing: [GraphStep], column: Int, upperColumn: Int) -> Bool {
        let straights = landing.filter { $0.from == column }
        let joins = landing.filter { $0.from != column }
        return straights.count == 1 && joins.allSatisfy { $0.from == upperColumn }
    }

    /// Values that appear more than once, leaving `exempt` out, ascending.
    private static func repeated(_ columns: [Int], except exempt: Int?) -> [Int] {
        var counts: [Int: Int] = [:]
        for column in columns where column != exempt {
            counts[column, default: 0] += 1
        }
        return counts.filter { $0.value > 1 }.keys.sorted()
    }
}
