import SwiftUI

/// Left column of Reviews: Team / Mine, when the inbox was last read and
/// Refresh; the notices that hold for the whole inbox; then the open pull
/// requests grouped by repo (Rulings 8 and 9).
struct ReviewsList: View {
    let store: ReviewsStore
    let onSelect: (InboxPull) -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            header
            notices
            content
        }
        // The pinned repo headers are painted with it.
        .background(theme.colors.bgContent)
    }

    // MARK: Header

    /// As the Pull requests scope bar: the filter above the list.
    private var header: some View {
        HStack(spacing: Spacing.s8) {
            SegmentedControl<ReviewsFilter>(
                ReviewsFilter.allCases.map { ($0, $0.title) },
                selection: Bindable(store).filter
            )
            .fixedSize()
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
            EmptyState(symbol: "arrow.triangle.pull",
                       title: String(localized: "No open pull requests in the repositories you follow."))
        case .groups(let groups):
            ScrollView {
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
                            }
                            if let error = group.error {
                                errorRow(error)
                            }
                        } header: {
                            ReviewGroupHeader(repo: group.repo)
                        }
                    }
                }
                .padding(.horizontal, Spacing.s8)
                .padding(.bottom, Spacing.s8)
            }
        }
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
