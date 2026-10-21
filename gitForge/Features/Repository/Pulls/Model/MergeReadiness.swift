import Foundation

/// What the detail's banner says about merging. The verdict is the host's
/// (`HostMergeStatus`); gitForge only adds what it can explain from the CI
/// checks and the reviews. Without the host's say it falls back to its own
/// reading, and never offers to merge.
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
    /// The verdict came from the host, not from gitForge's own reading.
    var fromHost = false

    /// Merge… is offered only when the host itself says it can merge.
    var canMerge: Bool { fromHost && kind == .ready }

    /// The reasons as the banner's sentence: "1 failing check · ….", or
    /// `nil` when there are none.
    var summary: String? {
        reasons.isEmpty ? nil : Self.sentence(reasons)
    }

    /// Reasons joined with " · ", capitalized, with a full stop.
    static func sentence(_ reasons: [String]) -> String {
        let joined = reasons.joined(separator: " · ")
        return joined.prefix(1).uppercased() + joined.dropFirst() + "."
    }

    static func evaluate(state: PullRequest.State,
                         mergeable: Bool?,
                         checks: [CICheck],
                         reviewers: [PullRequestDetail.Reviewer],
                         hostStatus: HostMergeStatus? = nil) -> MergeReadiness? {
        guard state == .open || state == .draft else { return nil }
        let failed = checks.filter { $0.state == .failed }.count
        let running = checks.filter { $0.state == .running || $0.state == .queued }.count
        let passed = checks.filter { $0.state == .passed }.count
        let changesRequested = reviewers.filter { $0.state == .changesRequested }.count
        let pendingReviews = reviewers.filter { $0.state == .pending }.count

        // What the checks and reviews say; conflicts and drafts are the
        // host's to report once it gives a verdict.
        var checksAndReviews: [String] = []
        if failed > 0 {
            checksAndReviews.append(failed == 1 ? String(localized: "1 failing check")
                                                : String(localized: "\(failed) failing checks"))
        }
        if changesRequested > 0 {
            checksAndReviews.append(changesRequested == 1 ? String(localized: "1 review requesting changes")
                                                          : String(localized: "\(changesRequested) reviews requesting changes"))
        }

        var waiting: [String] = []
        if running > 0 { waiting.append(String(localized: "\(running) in progress")) }
        if pendingReviews > 0 {
            waiting.append(pendingReviews == 1 ? String(localized: "1 review pending")
                                               : String(localized: "\(pendingReviews) reviews pending"))
        }

        guard let hostStatus else {
            let blocking = (mergeable == false ? [HostMergeStatus.conflicts] : []) + checksAndReviews
                + (state == .draft ? [HostMergeStatus.draft] : [])
            let kind: Kind = !blocking.isEmpty ? .blocked : (!waiting.isEmpty ? .waiting : .ready)
            return MergeReadiness(kind: kind, reasons: blocking + waiting, passed: passed, running: running, failed: failed)
        }

        var reasons: [String] = []
        // GitHub's `blocked` names no rule: say what gitForge can see.
        if hostStatus.includesLocalReasons { reasons += checksAndReviews + waiting }
        reasons += hostStatus.reasons
        if hostStatus.failingChecksOptional, failed > 0 {
            reasons.append(failed == 1 ? String(localized: "1 check failing (not required)")
                                       : String(localized: "\(failed) checks failing (not required)"))
        }
        let kind: Kind = switch hostStatus.verdict {
        case .ready: .ready
        case .waiting: .waiting
        case .blocked: .blocked
        }
        return MergeReadiness(kind: kind, reasons: reasons, passed: passed, running: running, failed: failed, fromHost: true)
    }
}
