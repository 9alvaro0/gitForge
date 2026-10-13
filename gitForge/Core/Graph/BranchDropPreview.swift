import Foundation

/// What dropping one branch on a target does to the graph, counted on the
/// loaded commits, for the drag HUD's mini graph.
nonisolated struct BranchDropPreview: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Branch on branch (merge or rebase, chosen after the drop):
        /// commits only the dragged branch has, and only the target has.
        case integrate(sourceOnly: Int, targetOnly: Int)
        /// Branch on a commit: commits the branch stops containing, and
        /// commits it starts containing.
        case move(dropped: Int, gained: Int)
    }

    let kind: Kind

    /// `nil` when either tip isn't loaded or the two share no loaded
    /// ancestor: the counts would be guesses.
    static func integrate(source: String, target: String, in commits: [Commit]) -> BranchDropPreview? {
        counts(source, target, commits).map { BranchDropPreview(kind: .integrate(sourceOnly: $0, targetOnly: $1)) }
    }

    static func move(from oldTip: String, to newTip: String, in commits: [Commit]) -> BranchDropPreview? {
        counts(oldTip, newTip, commits).map { BranchDropPreview(kind: .move(dropped: $0, gained: $1)) }
    }

    /// Commits reachable only from `a`, and only from `b`.
    private static func counts(_ a: String, _ b: String, _ commits: [Commit]) -> (Int, Int)? {
        let fromA = CommitAncestry.reachable(from: a, in: commits)
        let fromB = CommitAncestry.reachable(from: b, in: commits)
        guard !fromA.isEmpty, !fromB.isEmpty, !fromA.isDisjoint(with: fromB) else { return nil }
        return (fromA.subtracting(fromB).count, fromB.subtracting(fromA).count)
    }

    // MARK: Captions

    /// Merge `source` into `target`.
    static func mergeCaption(sourceOnly: Int, targetOnly: Int, source: String, target: String) -> String {
        if sourceOnly == 0 { return "\(target) already has \(source)" }
        if targetOnly == 0 { return "Fast-forwards \(target) by \(commits(sourceOnly))" }
        return "A merge commit brings \(commits(sourceOnly)) into \(target)"
    }

    /// Rebase `source` onto `target`.
    static func rebaseCaption(sourceOnly: Int, targetOnly: Int, source: String, target: String) -> String {
        if targetOnly == 0 { return "\(source) is already on top of \(target)" }
        if sourceOnly == 0 { return "\(source) moves up to \(target)" }
        return "Replays \(commits(sourceOnly)) after \(target)'s \(commits(targetOnly))"
    }

    static func moveCaption(dropped: Int, gained: Int, branch: String) -> String {
        switch (dropped, gained) {
        case (0, let gained): "\(branch) moves forward \(commits(gained))"
        case (let dropped, 0): "\(branch) moves back \(commits(dropped))"
        case let (dropped, gained): "\(branch) leaves \(commits(dropped)) and takes \(commits(gained)) from another line"
        }
    }

    private static func commits(_ count: Int) -> String {
        count == 1 ? "1 commit" : "\(count) commits"
    }
}
