import Foundation

/// How a commit's node is drawn (redesign spec §4.5): node shape encodes
/// kind, so lane colour never carries meaning alone.
nonisolated enum GraphNodeStyle: Equatable, Sendable {
    /// Filled dot.
    case commit
    /// Hollow ring.
    case merge
    /// Outer ring with an inner dot.
    case head
    /// Dashed square.
    case stash

    static func `for`(_ row: GraphRowLayout, isHeadCommit: Bool) -> GraphNodeStyle {
        if row.commitIsStash { return .stash }
        if isHeadCommit { return .head }
        return row.isMerge ? .merge : .commit
    }
}

/// Locates the HEAD branch's lane so it can take the accent colour.
nonisolated enum GraphHead {
    /// Branch id of the row holding `headSha`; `nil` when HEAD isn't loaded.
    static func branchId(headSha: String?, commits: [Commit], layouts: [GraphRowLayout]) -> Int? {
        guard let headSha,
              let index = commits.firstIndex(where: { $0.sha == headSha }),
              layouts.indices.contains(index) else { return nil }
        return layouts[index].commitBranchId
    }
}
