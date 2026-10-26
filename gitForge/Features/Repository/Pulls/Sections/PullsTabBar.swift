import SwiftUI

/// The bar of the Pull requests section (U1 Ruling 8), across its whole width
/// and over every tab, the full-width states included: the tabs, each with its
/// number once known, and Refresh for the tab shown, after when the inbox was
/// last read on Team and Mine. Narrowed to a repo, the inbox has no halves to
/// pick: the tabs give way to `ReviewsRepoFilterBar`, under the bar.
struct PullsTabBar: View {
    let reviews: ReviewsStore
    /// The open repository's store, behind Open and Closed; `nil` with no
    /// repository open, when only Team and Mine are offered.
    let repositoryStore: PullRequestStore?
    /// The tab shown (`PullsTab.shown`).
    let tab: PullsTab

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: Spacing.s8) {
            if tab.half == nil || reviews.filteredRepo == nil {
                SegmentedControl<PullsTab>(
                    PullsTab.available(hasRepository: repositoryStore != nil).map { ($0, label(for: $0)) },
                    selection: Binding(get: { tab }, set: { reviews.tab = $0 })
                )
                .fixedSize()
            }
            Spacer(minLength: 0)
            if let repositoryStore, tab.half == nil {
                refreshButton(isBusy: repositoryStore.isLoading, help: repositoryRefreshHelp(repositoryStore)) {
                    Task { await repositoryStore.refresh() }
                }
            } else if reviews.hasAccounts {
                if let updated = reviews.lastRefreshedAt {
                    // Ticks over while the section stays on screen.
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text("Updated \(DateDisplayMode.elapsed(since: updated, reference: context.date))")
                            .textRole(.caption)
                            .foregroundStyle(theme.colors.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                refreshButton(isBusy: reviews.isRefreshing, help: String(localized: "Refresh")) {
                    // Reads the memberships and rename lookups again too (R3 Ruling 9).
                    Task { await reviews.refresh(force: true, rereadLists: true) }
                }
            }
        }
        .padding(.horizontal, Spacing.s12)
        .frame(height: 44)
    }

    /// "Open 12": the tab's title and, once known, how many rows it lists.
    private func label(for tab: PullsTab) -> String {
        count(for: tab).map { "\(tab.title) \($0)" } ?? tab.title
    }

    /// Team and Mine count the inbox's rows of their half; Open and Closed,
    /// the repository's list once it shows: "Open 0" over its loading or
    /// "connect an account" would be wrong.
    private func count(for tab: PullsTab) -> Int? {
        if let half = tab.half { return reviews.count(for: half) }
        guard let scope = tab.listScope, let repositoryStore, repositoryStore.isListReady else { return nil }
        return repositoryStore.count(for: scope)
    }

    /// A spinner in its place while what it would read is being read.
    @ViewBuilder
    private func refreshButton(isBusy: Bool, help: String, action: @escaping () -> Void) -> some View {
        if isBusy {
            ProgressView()
                .controlSize(.small)
                .frame(width: 26, height: 26)
        } else {
            IconButton(symbol: "arrow.clockwise", accessibilityLabel: String(localized: "Refresh"), action: action)
                .help(help)
        }
    }

    /// Whole phrases per provider, as the toolbar's Refresh had them.
    private func repositoryRefreshHelp(_ store: PullRequestStore) -> String {
        store.host?.provider == .gitlab ? String(localized: "Refresh merge requests")
                                        : String(localized: "Refresh pull requests")
    }
}
