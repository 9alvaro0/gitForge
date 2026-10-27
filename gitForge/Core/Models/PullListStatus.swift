import Foundation

/// What stands between an open pull request and its merge, as the host's
/// list tells it: one verdict per row, the most pressing one. GitLab's list
/// carries it (`detailed_merge_status`); GitHub's comes from one GraphQL read
/// per repo. A row without one (a draft, a closed one, a GitHub read that
/// failed) shows no verdict: the detail still has the full picture.
nonisolated struct PullListStatus: Equatable, Sendable, Codable {
    enum Kind: String, Equatable, Sendable, Codable, CaseIterable {
        /// Nothing in the way: it can be merged.
        case ready
        /// The host is still working out whether it can be merged.
        case checking
        /// CI is running.
        case running
        /// CI failed, or has to pass and hasn't.
        case failing
        /// Conflicts with the target branch.
        case conflicts
        /// Behind the target branch: it needs a rebase or an update.
        case behind
        /// Waiting for approvals.
        case needsApproval
        /// A reviewer asked for changes.
        case changesRequested
        /// Its threads have to be resolved first.
        case unresolvedThreads
        /// Anything else the host holds it back for (another merge request,
        /// a project rule…).
        case blocked
    }

    let kind: Kind
    /// The host's own word for it (`detailed_merge_status`,
    /// `mergeStateStatus`), for the help text.
    var hostCode: String? = nil

    var tone: PullStatusTone { kind.tone }
}

/// How a row's verdict is coloured: the theme's state colours, never alone
/// (each verdict has its glyph and word too).
nonisolated enum PullStatusTone: String, Equatable, Sendable, CaseIterable {
    /// Ready to merge.
    case ok
    /// Something is still running.
    case info
    /// Waiting on people: approvals, changes, threads, a rebase.
    case warn
    /// Broken: CI failed, conflicts, blocked.
    case danger
    /// No verdict: a draft, or the host said nothing.
    case neutral
}

nonisolated extension PullListStatus.Kind {
    var tone: PullStatusTone {
        switch self {
        case .ready: .ok
        case .checking, .running: .info
        case .behind, .needsApproval, .changesRequested, .unresolvedThreads: .warn
        case .failing, .conflicts, .blocked: .danger
        }
    }
}

// MARK: - From the hosts

nonisolated extension PullListStatus {
    /// GitLab's `detailed_merge_status` (15.6+), else the older
    /// `merge_status` and `has_conflicts`. `nil` for a draft or a merge
    /// request that isn't open: the row says that on its own.
    static func gitLab(detailed: String?, legacy: String?, hasConflicts: Bool?) -> PullListStatus? {
        if let detailed {
            let kind: Kind
            switch detailed {
            case "mergeable": kind = .ready
            case "checking", "unchecked", "preparing", "approvals_syncing": kind = .checking
            case "ci_still_running": kind = .running
            case "ci_must_pass": kind = .failing
            case "conflict": kind = .conflicts
            case "need_rebase": kind = .behind
            case "not_approved": kind = .needsApproval
            case "requested_changes": kind = .changesRequested
            case "discussions_not_resolved": kind = .unresolvedThreads
            case "draft_status", "not_open": return nil
            default: kind = .blocked
            }
            return PullListStatus(kind: kind, hostCode: detailed)
        }
        if hasConflicts == true { return PullListStatus(kind: .conflicts, hostCode: legacy) }
        switch legacy {
        case nil: return nil
        case "can_be_merged": return PullListStatus(kind: .ready, hostCode: legacy)
        case "cannot_be_merged": return PullListStatus(kind: .conflicts, hostCode: legacy)
        default: return PullListStatus(kind: .checking, hostCode: legacy)
        }
    }

    /// GitHub's GraphQL fields of an open pull request, most pressing first:
    /// conflicts, failing or running checks, the review decision, then the
    /// merge state. `nil` for a draft.
    /// - Parameters:
    ///   - mergeable: `MERGEABLE`, `CONFLICTING` or `UNKNOWN`.
    ///   - mergeState: `mergeStateStatus` (`CLEAN`, `BLOCKED`, `BEHIND`…), when read.
    ///   - reviewDecision: `APPROVED`, `CHANGES_REQUESTED` or `REVIEW_REQUIRED`.
    ///   - checks: the head commit's `statusCheckRollup.state`.
    static func gitHub(mergeable: String?, mergeState: String?, reviewDecision: String?,
                       checks: String?) -> PullListStatus? {
        if mergeState == "DRAFT" { return nil }
        let code = mergeState ?? mergeable
        if mergeable == "CONFLICTING" || mergeState == "DIRTY" { return PullListStatus(kind: .conflicts, hostCode: code) }
        switch checks {
        case "FAILURE", "ERROR": return PullListStatus(kind: .failing, hostCode: code)
        case "PENDING", "EXPECTED": return PullListStatus(kind: .running, hostCode: code)
        default: break
        }
        switch reviewDecision {
        case "CHANGES_REQUESTED": return PullListStatus(kind: .changesRequested, hostCode: code)
        case "REVIEW_REQUIRED": return PullListStatus(kind: .needsApproval, hostCode: code)
        default: break
        }
        switch mergeState {
        case "BEHIND": return PullListStatus(kind: .behind, hostCode: code)
        case "BLOCKED": return PullListStatus(kind: .blocked, hostCode: code)
        case "CLEAN", "HAS_HOOKS", "UNSTABLE": return PullListStatus(kind: .ready, hostCode: code)
        default:
            // No merge state (not read, or still `UNKNOWN`): `mergeable` alone.
            return PullListStatus(kind: mergeable == "MERGEABLE" ? .ready : .checking, hostCode: code)
        }
    }
}

// MARK: - Words

nonisolated extension PullListStatus {
    /// The row's chip: a word or two.
    var label: String {
        switch kind {
        case .ready: String(localized: "Ready to merge")
        case .checking: String(localized: "Checking")
        case .running: String(localized: "CI running")
        case .failing: String(localized: "CI failed")
        case .conflicts: String(localized: "Conflicts")
        case .behind: String(localized: "Out of date")
        case .needsApproval: String(localized: "Needs approval")
        case .changesRequested: String(localized: "Changes requested")
        case .unresolvedThreads: String(localized: "Open threads")
        case .blocked: String(localized: "Blocked")
        }
    }

    /// The chip's help: what it means, with GitLab's own reason when it
    /// blocks for one gitForge has no word of its own for.
    var help: String {
        switch kind {
        case .ready: String(localized: "Nothing stands in the way of merging it.")
        case .checking: String(localized: "The host is still checking whether it can be merged.")
        case .running: String(localized: "Its CI is still running.")
        case .failing: String(localized: "Its CI failed, or has to pass before merging.")
        case .conflicts: String(localized: "It conflicts with the target branch.")
        case .behind: String(localized: "It's behind the target branch and needs a rebase.")
        case .needsApproval: String(localized: "It needs approval before merging.")
        case .changesRequested: String(localized: "A reviewer requested changes.")
        case .unresolvedThreads: String(localized: "All threads must be resolved before merging.")
        case .blocked:
            if let hostCode, let reason = GitLabPullRequestProvider.knownBlockedReason(hostCode) {
                String(localized: "Can't be merged yet: \(reason).")
            } else {
                String(localized: "The host doesn't allow merging it yet.")
            }
        }
    }

    /// The glyph next to the word.
    var symbol: String {
        switch kind {
        case .ready: "checkmark.circle.fill"
        case .checking: "clock"
        case .running: "circle.lefthalf.filled"
        case .failing: "xmark.octagon.fill"
        case .conflicts: "exclamationmark.triangle.fill"
        case .behind: "arrow.down.circle"
        case .needsApproval: "person.badge.clock"
        case .changesRequested: "arrow.uturn.backward.circle"
        case .unresolvedThreads: "text.bubble"
        case .blocked: "nosign"
        }
    }
}

nonisolated extension PullRequest {
    /// The tone a row is drawn in: its verdict's, grey for a draft or an
    /// open one the host said nothing about. Merged and closed ones have
    /// their own state pill and no tone.
    var statusTone: PullStatusTone {
        guard state == .open, let listStatus else { return .neutral }
        return listStatus.tone
    }

    /// Open, not a draft, and the host says it can be merged: the row offers
    /// Merge….
    var isReadyToMerge: Bool {
        state == .open && listStatus?.kind == .ready
    }
}

// MARK: - A repo's summary

/// How many of a repo's rows are in one tone, for its heading.
nonisolated struct PullToneCount: Equatable, Sendable {
    let tone: PullStatusTone
    let count: Int
}

nonisolated extension PullStatusTone {
    /// The order a heading lists its tones in: what needs attention first.
    static let summaryOrder: [PullStatusTone] = [.danger, .warn, .info, .ok, .neutral]

    /// The tones of `pulls`, in `summaryOrder`, leaving out those with none.
    static func summary(of pulls: [PullRequest]) -> [PullToneCount] {
        var counts: [PullStatusTone: Int] = [:]
        for pull in pulls { counts[pull.statusTone, default: 0] += 1 }
        return summaryOrder.compactMap { tone in
            counts[tone].map { PullToneCount(tone: tone, count: $0) }
        }
    }
}
