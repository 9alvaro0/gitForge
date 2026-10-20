import Foundation

/// What the detail's banner says about merging, from data the provider
/// already gives: mergeability, the CI checks and the reviews.
nonisolated struct MergeReadiness: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Something must change before it can merge.
        case blocked
        /// Nothing wrong yet, but checks or reviews are still out.
        case waiting
        /// Nothing in the way that we know of.
        case ready
    }

    let kind: Kind
    /// Human reasons, most important first ("1 failing check", "conflicts"…).
    let reasons: [String]
    let passed: Int
    let running: Int
    let failed: Int

    static func evaluate(state: PullRequest.State,
                         mergeable: Bool?,
                         checks: [CICheck],
                         reviewers: [PullRequestDetail.Reviewer]) -> MergeReadiness? {
        guard state == .open || state == .draft else { return nil }
        let failed = checks.filter { $0.state == .failed }.count
        let running = checks.filter { $0.state == .running || $0.state == .queued }.count
        let passed = checks.filter { $0.state == .passed }.count
        let changesRequested = reviewers.filter { $0.state == .changesRequested }.count
        let pendingReviews = reviewers.filter { $0.state == .pending }.count

        var blocking: [String] = []
        if mergeable == false { blocking.append(String(localized: "conflicts with the target branch")) }
        if failed > 0 {
            blocking.append(failed == 1 ? String(localized: "1 failing check")
                                        : String(localized: "\(failed) failing checks"))
        }
        if changesRequested > 0 {
            blocking.append(changesRequested == 1 ? String(localized: "1 review requesting changes")
                                                  : String(localized: "\(changesRequested) reviews requesting changes"))
        }
        if state == .draft { blocking.append(String(localized: "still a draft")) }

        var waiting: [String] = []
        if running > 0 { waiting.append(String(localized: "\(running) in progress")) }
        if pendingReviews > 0 {
            waiting.append(pendingReviews == 1 ? String(localized: "1 review pending")
                                               : String(localized: "\(pendingReviews) reviews pending"))
        }

        let kind: Kind = !blocking.isEmpty ? .blocked : (!waiting.isEmpty ? .waiting : .ready)
        return MergeReadiness(kind: kind, reasons: blocking + waiting, passed: passed, running: running, failed: failed)
    }
}
