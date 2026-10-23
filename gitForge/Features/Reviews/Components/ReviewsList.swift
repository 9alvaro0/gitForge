import SwiftUI

/// Left column of Reviews: Team / Mine, when the inbox was last read and
/// Refresh; the repo the inbox is narrowed to, if any; the notices that hold
/// for the whole inbox; then the open pull requests grouped by repo (Rulings
/// 8 and 9) and the Others opened from a link (R2 Ruling 9). A row selected
/// from outside the list scrolls into view (`ReviewsStore.revealRequest`).
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
                ReviewsRepoFilterBar(repo: repo) { store.showAllRepos() }
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
                Task { await store.refresh(force: true) }
            }
            .help(String(localized: "Refresh"))
        }
    }

    // MARK: Notices

    @ViewBuilder
    private var notices: some View {
        let reconnect = store.accountsToReconnect
        if store.droppedByLimit > 0 || !reconnect.isEmpty {
            VStack(spacing: Spacing.s6) {
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
                        detail: nil,
                        action: nil
                    )
                }
            }
            .padding(.horizontal, Spacing.s8)
            .padding(.bottom, Spacing.s8)
        }
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
                    ReviewRepoActionButton(repo: repo)
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
        LazyVStack(alignment: .leading, spacing: Spacing.s2, pinnedViews: [.sectionHeaders]) {
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
                    ReviewGroupHeader(repo: group.repo)
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
