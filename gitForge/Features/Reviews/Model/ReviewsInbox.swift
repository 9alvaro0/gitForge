import Foundation

/// Which half of the inbox shows: the pull requests of others or the user's
/// own (Ruling 8). Drafts show in their author's half.
nonisolated enum ReviewsFilter: String, CaseIterable, Identifiable, Sendable {
    case team, mine

    var id: String { rawValue }
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
