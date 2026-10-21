import Foundation

/// Whether the host lets the PR/MR merge right now, as it says (GitHub's
/// `mergeable_state`, GitLab's `detailed_merge_status`), in words.
nonisolated struct HostMergeStatus: Equatable, Sendable {
    enum Verdict: Equatable, Sendable { case ready, waiting, blocked }

    let verdict: Verdict
    /// Why, in the host's terms, already localized.
    var reasons: [String] = []
    /// GitHub's `blocked` doesn't say which rule: the reasons gitForge can
    /// work out (failing checks, reviews) go first.
    var includesLocalReasons = false
    /// GitHub's `unstable`: failing checks that aren't required.
    var failingChecksOptional = false
    /// GitHub works mergeability out in the background: ask again shortly.
    var stillComputing = false

    static var checking: String { String(localized: "checking mergeability…") }
    static var conflicts: String { String(localized: "conflicts with the target branch") }
    static var draft: String { String(localized: "still a draft") }
}
