import SwiftUI

/// Left column of Reviews: Team / Mine, when the inbox was last read and
/// Refresh; the repo the inbox is narrowed to, if any; the notices that hold
/// for the whole inbox (the pattern gitForge proposes first); then the open
/// pull requests grouped by repo (Rulings 8 and 9) and the Others opened from
/// a link (R2 Ruling 9). A row selected from outside the list scrolls into
/// view (`ReviewsStore.revealRequest`).
struct ReviewsList: View {
    let store: ReviewsStore
    let onSelect: (InboxPull) -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            header
            if let repo = store.filteredRepo {
                // A row of its own, the column's whole width: the path and
                // its button would crowd the header (R2 Ruling 7).
                ReviewsRepoFilterBar(repo: repo, onShowAll: { store.showAllRepos() },
                                     onFollow: followable(repo).map { found in { follow(found) } })
                    .padding(.horizontal, Spacing.s12)
                    .padding(.bottom, Spacing.s8)
            }
            notices
            content
        }
        // The pinned repo headers are painted with it.
        .background(theme.colors.bgContent)
    }

    // MARK: Header

    /// As the Pull requests scope bar: the filter above the list. Narrowed
    /// to a repo, Team / Mine goes: the list shows both halves (R2 Ruling 7).
    private var header: some View {
        HStack(spacing: Spacing.s8) {
            if store.filteredRepo == nil {
                SegmentedControl<ReviewsFilter>(
                    ReviewsFilter.allCases.map { ($0, $0.title) },
                    selection: Bindable(store).filter
                )
                .fixedSize()
            }
            Spacer(minLength: 0)
            if let updated = store.lastRefreshedAt {
                // Ticks over while the inbox stays on screen.
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text("Updated \(DateDisplayMode.elapsed(since: updated, reference: context.date))")
                        .textRole(.caption)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            refreshButton
        }
        .padding(.horizontal, Spacing.s12)
        .frame(height: 44)
    }

    @ViewBuilder
    private var refreshButton: some View {
        if store.isRefreshing {
            ProgressView()
                .controlSize(.small)
                .frame(width: 26, height: 26)
        } else {
            IconButton(symbol: "arrow.clockwise", accessibilityLabel: String(localized: "Refresh")) {
                // Reads the memberships and rename lookups again too (R3 Ruling 9).
                Task { await store.refresh(force: true, rereadLists: true) }
            }
            .help(String(localized: "Refresh"))
        }
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

    /// "Hide from Reviews" on the heading of a followed repo (R3 Ruling 15,
    /// Ruling Q); `nil` on a repo opened from a search, which hiding wouldn't
    /// change.
    private func hideAction(_ repo: ReviewRepo, followed: Set<String>) -> (() -> Void)? {
        guard followed.contains(repo.id) else { return nil }
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
        let followed = store.followedKeys
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
                    ReviewGroupHeader(repo: group.repo, onHide: hideAction(group.repo, followed: followed))
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
