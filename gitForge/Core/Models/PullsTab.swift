import Foundation

/// The tabs of the Pull requests section (U1 spec §4.2): the inbox's two
/// halves, Team and Mine, and, with a repository open, that repository's own
/// lists, Open and Closed. The raw value is what's saved between launches.
nonisolated enum PullsTab: String, CaseIterable, Identifiable, Sendable {
    case team, mine, open, closed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .team: ReviewsFilter.team.title
        case .mine: ReviewsFilter.mine.title
        case .open: PullListScope.open.title
        case .closed: PullListScope.closed.title
        }
    }

    /// The half of the inbox this tab shows; `nil` for the repository's lists.
    var half: ReviewsFilter? {
        switch self {
        case .team: .team
        case .mine: .mine
        case .open, .closed: nil
        }
    }

    /// The repository list this tab shows; `nil` for the inbox's halves.
    var repositoryList: PullListState? {
        switch self {
        case .team, .mine: nil
        case .open: .open
        case .closed: .closed
        }
    }

    /// The scope of the repository's store this tab shows
    /// (`PullRequestStore.scope`); `nil` for the inbox's halves.
    var listScope: PullListScope? {
        switch self {
        case .team, .mine: nil
        case .open: .open
        case .closed: .closed
        }
    }

    /// The tab for an inbox `half` and the repository list shown over it, if
    /// any: the list wins, the half is only the one the inbox keeps under it.
    init(half: ReviewsFilter, repositoryList: PullListState?) {
        switch repositoryList {
        case .open: self = .open
        case .closed: self = .closed
        case nil: self = half == .team ? .team : .mine
        }
    }

    /// The tabs there are to pick from: the repository's lists only exist
    /// with a repository open.
    static func available(hasRepository: Bool) -> [PullsTab] {
        hasRepository ? allCases : [.team, .mine]
    }

    /// The tab to show for the one saved: Open and Closed need a repository,
    /// so without one the section shows Team. The saved tab isn't touched, so
    /// opening a repository again brings back the one that was picked.
    static func shown(_ saved: PullsTab, hasRepository: Bool) -> PullsTab {
        available(hasRepository: hasRepository).contains(saved) ? saved : .team
    }
}
