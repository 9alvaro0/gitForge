import Foundation

/// Which half of the inbox shows: the pull requests of others or the user's
/// own (Ruling 8). Drafts show in their author's half.
nonisolated enum ReviewsFilter: String, CaseIterable, Identifiable, Sendable {
    case team, mine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .team: String(localized: "Team")
        // The Pull requests scope's word.
        case .mine: String(localized: "pr.scope.mine", defaultValue: "Mine")
        }
    }
}

/// One row of the inbox: an open pull request and the repo it's in.
nonisolated struct InboxPull: Identifiable, Equatable, Sendable {
    let repo: ReviewRepo
    let pull: PullRequest

    var id: String { "\(repo.id)#\(pull.number)" }
}

/// A repo's rows in the inbox. `error` says why its pull requests couldn't be
/// read; such a repo comes last, without rows (Ruling 9).
nonisolated struct ReviewGroup: Identifiable, Equatable, Sendable {
    let repo: ReviewRepo
    let pulls: [InboxPull]
    let error: String?

    var id: String { repo.id }
}

/// What the Reviews detail offers where a repository's detail has its local
/// actions (spec §4.3): clone a repo that isn't on this Mac, or go to the
/// clone, where those actions are.
nonisolated enum ReviewRepoAction: Equatable, Sendable {
    /// Opens the clone sheet on this URL (Ruling 12).
    case clone(url: String)
    /// Makes the clone the active repository and opens the pull request in
    /// its Pull requests (Ruling 13).
    case openInRepository(URL)

    init(_ repo: ReviewRepo) {
        if let localURL = repo.localURL {
            self = .openInRepository(localURL)
        } else {
            self = .clone(url: repo.cloneURL)
        }
    }
}

/// The open detail's pull request, as the inbox watches it for a merge or a
/// close made from Reviews (Ruling 14).
nonisolated struct ReviewDetailState: Equatable, Sendable {
    let itemID: InboxPull.ID
    let state: PullRequest.State
    /// A merge from the detail is running: its sheet stays up until the
    /// store has read the result back.
    var isMerging = false

    /// The same pull request went from open (or a draft) to merged or
    /// closed, and its merge, if any, is over: its repo is read again so it
    /// leaves the inbox. Moving to another pull request doesn't count.
    static func leftOpen(from old: ReviewDetailState?, to new: ReviewDetailState?) -> Bool {
        guard let old, let new, old.itemID == new.itemID else { return false }
        return old.isListed && !new.isListed
    }

    /// Still a row of the inbox: open, a draft, or being merged (the row
    /// goes once the merge sheet is done with it).
    private var isListed: Bool {
        isMerging || state == .open || state == .draft
    }
}
