import SwiftUI

/// Left column of Team and Mine, under the section's tab bar
/// (`PullsTabBar`): the repo the inbox is narrowed to, if any; the notices
/// that hold for the whole inbox (the pattern gitForge proposes first); then
/// the open pull requests grouped by repo (Rulings 8 and 9), the open
/// repository's first (U1 Ruling 3), and the Others opened from a link (R2
/// Ruling 9). A row selected from outside the list scrolls into view
/// (`ReviewsStore.revealRequest`).
struct ReviewsList: View {
    let store: ReviewsStore
    let onSelect: (InboxPull) -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            if let repo = store.filteredRepo {
                // In place of Team and Mine, which the tab bar no longer
                // offers: a row of its own, the column's whole width, where
                // the path and its button fit (R2 Ruling 7).
                ReviewsRepoFilterBar(repo: repo, onShowAll: { store.showAllRepos() },
                                     onFollow: followable(repo).map { found in { follow(found) } })
                    .padding(.horizontal, Spacing.s12)
                    .padding(.vertical, Spacing.s8)
            }
            notices
            content
        }
        // The pinned repo headers are painted with it.
        .background(theme.colors.bgContent)
    }

    // MARK: Notices

    @ViewBuilder
    private var notices: some View {
        let reconnect = store.accountsToReconnect
        if store.proposal != nil || store.droppedByLimit > 0 || !reconnect.isEmpty {
            VStack(spacing: Spacing.s6) {
                if let proposal = store.proposal {
                    proposalNotice(proposal)
                }
                ForEach(reconnect, id: \.account.id) { entry in
                    ReviewsNotice(
                        symbol: "exclamationmark.triangle.fill",
                        tint: theme.colors.warn,
                        soft: theme.colors.warnSoft,
                        title: String(localized: "Reconnect your \(entry.instance.kind.label) account"),
                        detail: [entry.account.login, entry.instance.host].compactMap { $0 }.joined(separator: " · "),
                        action: (String(localized: "Reconnect…"), {
                            appState.ui.connectAccountRequest = ConnectAccountRequest(instanceId: entry.instance.id,
                                                                                    replacing: entry.account.id)
                        })
                    )
                }
                if store.droppedByLimit > 0 {
                    ReviewsNotice(
                        symbol: "info.circle.fill",
                        tint: theme.colors.info,
                        soft: theme.colors.infoSoft,
                        // `FollowedRepos.limit`, spelled out for the translations.
                        title: String(localized: "\(store.droppedByLimit) repositories left out (limit of 100)."),
                        detail: String(localized: "Hide repositories or narrow your patterns in Settings."),
                        action: (String(localized: "Open Settings"), { appState.ui.openSettings(at: .reviews) })
                    )
                }
            }
            .padding(.horizontal, Spacing.s8)
            // Off the tab bar's rule, unless the filter bar is between them.
            .padding(.top, store.filteredRepo == nil ? Spacing.s8 : 0)
            .padding(.bottom, Spacing.s8)
        }
    }

    /// The pattern gitForge proposes, until it's answered (R3 Ruling 3). One
    /// that would take the inbox over the limit can't be followed: it points
    /// to Settings, where repos are hidden and patterns narrowed (Rulings 6
    /// and M).
    private func proposalNotice(_ proposal: PatternProposal) -> some View {
        let overLimit = store.exceedsLimit(proposal.total)
        let detail: String
        let action: (title: String, run: () -> Void)
        if overLimit {
            // `FollowedRepos.limit`, spelled out for the translations.
            detail = String(localized: "With them you'd follow \(proposal.total) repositories, over the limit of 100.")
            action = (String(localized: "Open Settings"), { appState.ui.openSettings(at: .reviews) })
        } else {
            detail = String(localized: "Follow the other \(proposal.adds) that fit too?")
            action = (String(localized: "Follow"), { acceptProposal() })
        }
        // A word joiner after each `/` keeps the pattern on one line: wrapped
        // at a slash, `apps/` and `*/android/*` read as two things.
        let pattern = proposal.pattern.text.replacingOccurrences(of: "/", with: "/\u{2060}")
        return ReviewsNotice(
            symbol: "lightbulb.fill",
            tint: theme.colors.accent,
            soft: theme.colors.accentSoft,
            title: String(localized: "Your repositories seem to follow \(pattern)."),
            detail: detail,
            action: action,
            secondary: (String(localized: "Not now"), { store.dismissProposal() })
        )
    }

    // MARK: Following

    /// What "Follow this repository" follows: `repo` while it's one opened
    /// from a search that isn't followed (R3 Ruling 13), on its instance;
    /// `nil` otherwise, or once its instance is gone.
    private func followable(_ repo: ReviewRepo) -> FoundRepo? {
        guard store.browsedRepos.contains(where: { $0.id == repo.id }),
              let instance = appState.accounts.instance(forHost: repo.host.host) else { return nil }
        return FoundRepo(host: repo.host, instanceId: instance.id, cloneURL: repo.cloneURL)
    }

    private func follow(_ repo: FoundRepo) {
        Task {
            if case .overLimit = await store.follow(repo) { warnOverLimit() }
        }
    }

    private func acceptProposal() {
        Task {
            if case .overLimit = await store.acceptProposal() { warnOverLimit() }
        }
    }

    /// Nothing changed: following would pass `FollowedRepos.limit` (R3 Ruling 6).
    private func warnOverLimit() {
        appState.ui.activeToast = ToastMessage(
            message: String(localized: "Following it would pass the limit of 100 repositories."), kind: .warn)
    }

    /// "Hide" on the heading of a followed repo (R3 Ruling 15, Ruling Q),
    /// and of the open repository that isn't followed, which hiding keeps out
    /// of Team and Mine (U1 Ruling 3); `nil` on a repo opened from a search,
    /// which hiding wouldn't change. `hideable`: the keys of both.
    private func hideAction(_ repo: ReviewRepo, hideable: Set<String>) -> (() -> Void)? {
        guard hideable.contains(repo.id) else { return nil }
        return { Task { await store.hide(repo.host) } }
    }

    // MARK: List

    @ViewBuilder
    private var content: some View {
        switch store.listContent {
        case .loading:
            PullsLoadingPlaceholder()
        case .empty:
            if let repo = store.filteredRepo {
                EmptyState(symbol: "arrow.triangle.pull",
                           title: String(localized: "No open pull requests in \(repo.host.slug).")) {
                    if let found = followable(repo) {
                        // Side by side while they fit, else one above the
                        // other, as wide as each other.
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: Spacing.s8) {
                                followButton(found)
                                    .fixedSize()
                                ReviewRepoActionButton(repo: repo)
                                    .fixedSize()
                            }
                            VStack(spacing: Spacing.s8) {
                                followButton(found, fullWidth: true)
                                ReviewRepoActionButton(repo: repo, fullWidth: true)
                            }
                            .fixedSize(horizontal: true, vertical: false)
                        }
                    } else {
                        ReviewRepoActionButton(repo: repo)
                    }
                }
            } else {
                EmptyState(symbol: "arrow.triangle.pull",
                           title: String(localized: "No open pull requests in the repositories you follow."))
            }
        case .groups(let groups, let others):
            ScrollViewReader { proxy in
                ScrollView {
                    rows(groups: groups, others: others)
                }
                // A row selected from outside the list (⌘K, a link, the × of
                // the repo filter) may be far down, or in the half just
                // switched to. A click leaves the list where it is.
                .onChange(of: store.revealRequest) { _, request in
                    if let request { bringIntoView(request.id, groups: groups, others: others, proxy: proxy) }
                }
                // The list shows up with a selection made elsewhere (a ⌘K
                // pick opens Reviews) or kept from before: that row in view,
                // once the rows are laid out.
                .onAppear {
                    guard let id = store.selectedID else { return }
                    Task { bringIntoView(id, groups: groups, others: others, proxy: proxy) }
                }
            }
        }
    }

    /// The empty state's "Follow this repository", before the repo's clone
    /// or open button as in the filter bar (R3 Ruling 13).
    private func followButton(_ found: FoundRepo, fullWidth: Bool = false) -> some View {
        GFButton(title: String(localized: "Follow this repository"), fullWidth: fullWidth) { follow(found) }
    }

    /// Scrolls only as much as it takes to show row `id`, and not at all
    /// when it's in view. Then, once laid out, the same for what sits just
    /// above it (`ReviewsScrollAbove`): scrolled up to, the row alone would
    /// end under its group's pinned heading; scrolled down to, or in view
    /// already, what's above it is in view too and nothing moves. A newer
    /// request by then cancels that second step: it has its own.
    private func bringIntoView(_ id: InboxPull.ID, groups: [ReviewGroup], others: [InboxPull],
                               proxy: ScrollViewProxy) {
        proxy.scrollTo(id)
        guard let above = ReviewsScrollAbove(id, groups: groups, others: others) else { return }
        let request = store.revealRequest
        Task {
            guard store.revealRequest == request else { return }
            switch above {
            case .row(let row): proxy.scrollTo(row)
            case .heading(let heading): proxy.scrollTo(heading)
            }
        }
    }

    private func rows(groups: [ReviewGroup], others: [InboxPull]) -> some View {
        var hideable = store.followedKeys
        if let visiting = store.visitingRepo { hideable.insert(visiting.id) }
        return LazyVStack(alignment: .leading, spacing: Spacing.s2, pinnedViews: [.sectionHeaders]) {
            ForEach(groups) { group in
                Section {
                    ForEach(group.pulls) { item in
                        PullRequestRow(
                            pullRequest: item.pull,
                            hostLabel: nil,
                            reference: item.repo.host.provider.reference(item.pull.number),
                            ci: nil,
                            isSelected: store.selectedID == item.id,
                            onSelect: { onSelect(item) }
                        )
                        .id(item.id)
                    }
                    if let error = group.error {
                        errorRow(error)
                    }
                } header: {
                    ReviewGroupHeader(repo: group.repo, onHide: hideAction(group.repo, hideable: hideable))
                        .id(ReviewsHeading.group(group.id))
                }
            }
            if !others.isEmpty {
                Section {
                    ForEach(others) { item in
                        ReviewOtherRow(
                            item: item,
                            isSelected: store.selectedID == item.id,
                            onSelect: { onSelect(item) },
                            onClose: { store.closeOther(item.id) }
                        )
                        .id(item.id)
                    }
                } header: {
                    ReviewOthersHeader()
                        .id(ReviewsHeading.others)
                }
            }
        }
        .padding(.horizontal, Spacing.s8)
        .padding(.bottom, Spacing.s8)
    }

    /// Why the repo's pull requests couldn't be read, in place of its rows.
    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11, weight: .semibold))
                .accessibilityHidden(true)
            Text(message)
                .textRole(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(theme.colors.textTertiary)
        .padding(.horizontal, Spacing.s12)
        .padding(.vertical, Spacing.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A heading of the inbox's list, as `ScrollViewProxy.scrollTo` finds it.
private enum ReviewsHeading: Hashable {
    case group(ReviewGroup.ID)
    case others
}

/// What sits just above a row of the list: the row before it in its group,
/// or, for a group's first row, the group's heading.
private enum ReviewsScrollAbove {
    case row(InboxPull.ID)
    case heading(ReviewsHeading)

    init?(_ id: InboxPull.ID, groups: [ReviewGroup], others: [InboxPull]) {
        for group in groups {
            if let index = group.pulls.firstIndex(where: { $0.id == id }) {
                self = index > 0 ? .row(group.pulls[index - 1].id) : .heading(.group(group.id))
                return
            }
        }
        guard let index = others.firstIndex(where: { $0.id == id }) else { return nil }
        self = index > 0 ? .row(others[index - 1].id) : .heading(.others)
    }
}

#Preview("Loaded") {
    @Previewable @State var theme = AppTheme()
    let store = ReviewsStore.preview(.loaded)
    ReviewsList(store: store, onSelect: { store.selectedID = $0.id })
        .task { await store.refresh(force: true) }
        .previewAppState(.preview)
        .frame(width: 380, height: 640)
        .background(theme.colors.bgContent)
        .appTheme(theme)
}

#Preview("Notices") {
    @Previewable @State var theme = AppTheme()
    let store = ReviewsStore.preview(.attention)
    ReviewsList(store: store, onSelect: { store.selectedID = $0.id })
        .task { await store.refresh(force: true) }
        .previewAppState(.preview)
        .frame(width: 320, height: 640)
        .background(theme.colors.bgContent)
        .appTheme(theme)
}
