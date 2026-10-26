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

    var id: String { Self.id(repoKey: repo.id, number: pull.number) }

    /// The id of pull request `number` in the repo whose key is `repoKey`.
    static func id(repoKey: String, number: Int) -> String { "\(repoKey)#\(number)" }
}

/// A repo's rows in the inbox. `error` says why its pull requests couldn't be
/// read; such a repo comes last, without rows (Ruling 9).
nonisolated struct ReviewGroup: Identifiable, Equatable, Sendable {
    let repo: ReviewRepo
    let pulls: [InboxPull]
    let error: String?

    var id: String { repo.id }
}

/// What the inbox's list shows under its header and notices.
nonisolated enum ReviewsListContent: Equatable, Sendable {
    /// The followed repos' groups, then the pull requests opened from a
    /// link that aren't among them (`ReviewsStore.visibleOthers`; R2 Ruling 9).
    case groups([ReviewGroup], others: [InboxPull] = [])
    /// A read is running, there's nothing to show yet and some repo hasn't
    /// been read (or none is followed yet).
    case loading
    /// No open pull requests in the repos followed, as far as the last read knows.
    case empty
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

/// What the detail of an inbox row offers for its local work (spec §4.3).
nonisolated enum PullsDetailAction: Equatable, Sendable {
    /// The row is in the repository open in gitForge: its own local actions.
    case local
    /// Another repository: open its clone, or clone it, as the Reviews detail did.
    case repo(ReviewRepoAction)
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

/// The link `ReviewsStore.openLink` is reading: the detail column names it
/// while it loads (R2 Ruling 11).
nonisolated struct PendingLink: Equatable, Sendable {
    let host: RemoteHost
    let number: Int
}

/// A row the inbox's list scrolls into view (`ReviewsStore.revealRequest`).
/// `serial` tells two requests for the same row apart: picking it again
/// brings it back into view.
nonisolated struct ReviewsRevealRequest: Equatable, Sendable {
    let id: InboxPull.ID
    let serial: UInt64
}

/// What opening a pull request's link came to (R2 Rulings 10 and 11).
nonisolated enum LinkOpenOutcome: Equatable, Sendable {
    /// A row of the inbox, a followed one or an Other.
    case opened(InboxPull.ID)
    /// No account of that instance could read it, and connecting one may:
    /// there's none, or one must be connected again.
    case connectAccount(instanceId: UUID)
    /// Why it couldn't be opened.
    case failed(String)
}

/// Where one instance's "Search all of <host>" stands (R3 Ruling 12): the
/// query it was made for, trimmed, and how far it got. ⌘K shows it only
/// while the text it searches, trimmed, is still `query`.
nonisolated struct HostSearchState: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        /// The host hasn't answered yet.
        case searching
        /// What it answered with; both lists empty is "Nothing found".
        case found(HostSearchResults)
        /// Why it couldn't search; picking the row tries again.
        case failed(String)
        /// No account of the instance signs, or its token was rejected twice.
        case connectAccount
    }

    let query: String
    var phase: Phase
}

/// What opening a repo found by searching a host came to (R3 Ruling 13).
nonisolated enum RepoOpenOutcome: Equatable, Sendable {
    /// The inbox is narrowed to it: a followed repo, or one browsed with its
    /// open pull requests among the Others.
    case shown(repoKey: String)
    /// No account of that instance could read it, and connecting one may:
    /// there's none, or one must be connected again.
    case connectAccount(instanceId: UUID)
    /// Why it couldn't be opened.
    case failed(String)
}
