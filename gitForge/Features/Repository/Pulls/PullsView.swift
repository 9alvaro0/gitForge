import SwiftUI

/// The open repository's own list and local actions, for Open and Closed
/// and for its rows in Team and Mine.
struct PullsRepository {
    let store: PullRequestStore
    /// What the detail does on disk: integrates the selected PR locally
    /// ("Resolve locally") and checks out its branch; session-wide work owned
    /// by `RepositoryViewModel`.
    let localActions: PullRequestLocalActions
}

/// The Pull requests section (pulls-unified spec §4.2): Team and Mine, the
/// open pull requests of the repos the user follows, and, with a repository
/// open, Open and Closed, that repository's own lists. The tab is the inbox's
/// (`ReviewsStore.tab`), kept between launches; without a repository, Open
/// and Closed fall back to Team.
struct PullsView: View {
    let reviews: ReviewsStore
    /// The repository open in gitForge; `nil` with none.
    let repository: PullsRepository?

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            PullsTabBar(reviews: reviews, repositoryStore: repository?.store, tab: tab)
            Rectangle().fill(theme.colors.separator).frame(height: 1)
            if let repository, tab.half == nil {
                PullsRepositoryPane(repository: repository)
            } else {
                PullsInboxPane(store: reviews, repository: repository)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.colors.bgContent)
        .navigationTitle(title)
        // Entering the section reads both, each within its own throttle, so
        // the open repository's group has rows whichever tab shows first (U1
        // Ruling 8).
        .task { await reviews.refresh() }
        .task { await loadRepository(for: tab, entering: true) }
        // Switching to Open or Closed reads only what the list lacks (U1
        // Ruling L); back to Team or Mine, the inbox within its throttle, as
        // showing Reviews did. Unstructured, as the scope bar was: another
        // switch mustn't cancel a read halfway.
        .onChange(of: tab) { old, new in
            if new.half == nil {
                Task { await loadRepository(for: new, entering: false) }
            } else if old.half == nil {
                Task { await reviews.refresh() }
            }
        }
    }

    /// The tab shown: the one saved, but Team for Open and Closed with no
    /// repository open (U1 Ruling 1).
    private var tab: PullsTab {
        PullsTab.shown(reviews.tab, hasRepository: repository != nil)
    }

    /// The repository's list for `tab`. Entering the section loads it within
    /// its throttle (U1 Ruling 8); switching to Open or Closed loads it only
    /// if it never loaded or shows an error, and otherwise just changes the
    /// scope, as the scope bar did (U1 Ruling L). Closed is read once either
    /// way: the scope is set before a load, which then reads Closed too
    /// (`PullRequestStore.load`), and `setScope` after it reads Closed the
    /// first time it's shown, if nothing did.
    private func loadRepository(for tab: PullsTab, entering: Bool) async {
        guard let store = repository?.store else { return }
        let scope = tab.listScope
        if entering || store.lastLoadedAt == nil || store.error != nil {
            if let scope { store.scope = scope }
            await store.load()
        }
        if let scope { await store.setScope(scope) }
    }

    /// "Merge requests" on Open and Closed of a GitLab repository; "Pull
    /// requests" everywhere else, Team and Mine mixing both.
    private var title: String {
        tab.half == nil && repository?.store.host?.provider == .gitlab
            ? String(localized: "Merge requests") : String(localized: "Pull requests")
    }
}

// MARK: - Team and Mine, with payments-app open

#Preview("Loaded") {
    @Previewable @State var theme = AppTheme()
    let open = PreviewOpenRepository.paymentsApp
    PullsView(reviews: .preview(.loaded, open: open), repository: open.pulls)
        .previewAppState(.preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}

#Preview("Selected, not cloned") {
    @Previewable @State var theme = AppTheme()
    let open = PreviewOpenRepository.paymentsApp
    let reviews: ReviewsStore = {
        let store = ReviewsStore.preview(.loaded, open: open)
        store.selectedID = "gitlab.example.test/apps/payments/backend/ledger#1203"
        return store
    }()
    PullsView(reviews: reviews, repository: open.pulls)
        .previewAppState(.preview)
        .frame(width: 1240, height: 760)
        .appTheme(theme)
}

#Preview("Empty") {
    @Previewable @State var theme = AppTheme()
    // A repo with no open pull request: it brings no group of its own.
    let open = PreviewOpenRepository(PreviewReviewsWorld.releaseTools)
    PullsView(reviews: .preview(.empty, open: open), repository: open.pulls)
        .previewAppState(.preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}

#Preview("No accounts") {
    @Previewable @State var theme = AppTheme()
    let open = PreviewOpenRepository.paymentsApp
    PullsView(reviews: .preview(.noAccounts, open: open), repository: open.pulls)
        .previewAppState(.preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}

#Preview("Over the limit") {
    @Previewable @State var theme = AppTheme()
    let open = PreviewOpenRepository.paymentsApp
    PullsView(reviews: .preview(.overLimit, open: open), repository: open.pulls)
        .previewAppState(.preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}

#Preview("Account to reconnect") {
    @Previewable @State var theme = AppTheme()
    let open = PreviewOpenRepository.paymentsApp
    PullsView(reviews: .preview(.attention, open: open), repository: open.pulls)
        .previewAppState(.preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}

#Preview("Others") {
    @Previewable @State var theme = AppTheme()
    let open = PreviewOpenRepository.paymentsApp
    let reviews = ReviewsStore.preview(.loaded, open: open)
    PullsView(reviews: reviews, repository: open.pulls)
        .task { await reviews.openPreviewOthers() }
        .previewAppState(.preview)
        .frame(width: 1240, height: 760)
        .appTheme(theme)
}

#Preview("Filtered by repo") {
    @Previewable @State var theme = AppTheme()
    let open = PreviewOpenRepository.paymentsApp
    let reviews = ReviewsStore.preview(.loaded, open: open)
    PullsView(reviews: reviews, repository: open.pulls)
        // A repo that isn't cloned, as ⌘K narrows to one.
        .task { await reviews.showPreviewRepo(PreviewReviewsWorld.ledger) }
        .previewAppState(.preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}

#Preview("Filtered, empty") {
    @Previewable @State var theme = AppTheme()
    let open = PreviewOpenRepository.paymentsApp
    let reviews = ReviewsStore.preview(.loaded, open: open)
    PullsView(reviews: reviews, repository: open.pulls)
        .task { await reviews.showPreviewRepo(PreviewReviewsWorld.releaseTools) }
        .previewAppState(.preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}

#Preview("Opening a link") {
    @Previewable @State var theme = AppTheme()
    let open = PreviewOpenRepository.paymentsApp
    let reviews = ReviewsStore.preview(.loaded, open: open)
    PullsView(reviews: reviews, repository: open.pulls)
        .task { await reviews.openPreviewSlowLink() }
        .previewAppState(.preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}

#Preview("Pattern proposal") {
    @Previewable @State var theme = AppTheme()
    let open = PreviewOpenRepository.paymentsApp
    PullsView(reviews: .preview(.proposal, open: open), repository: open.pulls)
        .previewAppState(.preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}

#Preview("Pattern proposal over the limit") {
    @Previewable @State var theme = AppTheme()
    let open = PreviewOpenRepository.paymentsApp
    PullsView(reviews: .preview(.proposalOverLimit, open: open), repository: open.pulls)
        .previewAppState(.preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}

#Preview("Browsed repository") {
    @Previewable @State var theme = AppTheme()
    let open = PreviewOpenRepository.paymentsApp
    let reviews = ReviewsStore.preview(.loaded, open: open)
    PullsView(reviews: reviews, repository: open.pulls)
        .task { await reviews.openPreviewFoundRepo(PreviewReviewsWorld.ossLib) }
        .previewAppState(.preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}

#Preview("Browsed repository, empty") {
    @Previewable @State var theme = AppTheme()
    let open = PreviewOpenRepository.paymentsApp
    let reviews = ReviewsStore.preview(.loaded, open: open)
    PullsView(reviews: reviews, repository: open.pulls)
        .task { await reviews.openPreviewFoundRepo(PreviewReviewsWorld.ossCli) }
        .previewAppState(.preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}

// MARK: - Open

#Preview("Open") {
    @Previewable @State var theme = AppTheme()
    let open = PreviewOpenRepository.paymentsApp
    PullsView(reviews: .preview(.loaded, open: open, tab: .open), repository: open.pulls)
        .previewAppState(.preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}

#Preview("Open, loading") {
    @Previewable @State var theme = AppTheme()
    let open: PreviewOpenRepository = {
        let open = PreviewOpenRepository.paymentsApp
        // A load that never lands: the store's own is skipped while one runs.
        open.pulls.store.items = []
        open.pulls.store.isLoading = true
        return open
    }()
    PullsView(reviews: .preview(.loaded, open: open, tab: .open), repository: open.pulls)
        .previewAppState(.preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}

#Preview("Open, token missing") {
    @Previewable @State var theme = AppTheme()
    let open = PreviewOpenRepository(PreviewReviewsWorld.paymentsApp, connected: false)
    PullsView(reviews: .preview(.loaded, open: open, tab: .open), repository: open.pulls)
        .previewAppState(.preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}

// MARK: - Without a repository, and with one nobody follows

#Preview("No repository open") {
    @Previewable @State var theme = AppTheme()
    // Saved on Open: with no repository, the section shows Team.
    PullsView(reviews: .preview(.loaded, open: nil, tab: .open), repository: nil)
        .previewAppState(.preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}

#Preview("Team, the open repository first") {
    @Previewable @State var theme = AppTheme()
    let open = PreviewOpenRepository.ossLib
    PullsView(reviews: .preview(.loaded, open: open), repository: open.pulls)
        .previewAppState(.preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}
