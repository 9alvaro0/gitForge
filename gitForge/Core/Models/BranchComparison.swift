import Foundation

/// A branch measured against the trunk (local `main`, else `master`) for
/// the Branches inspector.
nonisolated struct BranchComparison: Equatable, Sendable {
    /// Most commits listed under "Not in <trunk>".
    static let commitLimit = 5

    let trunk: String
    /// Commits on the branch that the trunk doesn't have.
    let ahead: Int
    /// Commits on the trunk that the branch doesn't have.
    let behind: Int
    /// The newest of the `ahead` commits, at most `commitLimit`.
    let commitsNotInTrunk: [Commit]
}
