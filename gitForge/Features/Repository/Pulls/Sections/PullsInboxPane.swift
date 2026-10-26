import SwiftUI

/// Team and Mine (U1 Ruling 8): the open pull requests of the repos the user
/// follows, and of the repository open in gitForge, grouped by repo, with the
/// selected one's detail on the right. One of the open repository opens in its
/// own store, with its local actions; one of another repo offers to open that
/// repo's clone or to clone it (spec §4.3).
struct PullsInboxPane: View {
    let store: ReviewsStore
    /// The repository open in gitForge, whose local actions its pull requests'
    /// detail carries; `nil` with none.
    let repository: PullsRepository?

    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme

    var body: some View {
        Group {
            if store.hasAccounts {
                splitLayout
            } else {
                EmptyState(symbol: WorkspaceSection.pulls.symbol,
                           title: String(localized: "Connect an account to see your team's pull requests.")) {
                    GFButton(title: String(localized: "Open Settings"), style: .primary) {
                        appState.ui.openSettings(at: .accounts)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Opens the selection's detail: picked in the list, or still
        // selected when the pane shows again. Keyed on the account too: a
        // refresh that reads the repo with another account replaces its
        // detail store (R2 Ruling 9), which has to open the pull request
        // again. And on whether it's the open repository's: its own store
        // takes over its detail once the inbox knows it (U1 Ruling 4).
        .task(id: store.selectedItem.map { "\($0.id)|\($0.repo.accountId)|\(store.isActive($0.repo))" }) {
            if let item = store.selectedItem { await store.open(item) }
        }
        .onChange(of: store.selectedItem?.id) { _, id in
            if id == nil { store.dropHiddenSelection() }
        }
        // Merged or closed from here: its repo is read again so it leaves
        // the list (Ruling 14), and an Other's row takes its new state (R2
        // Ruling 9).
        .onChange(of: detailState) { old, new in
            guard let item = store.selectedItem else { return }
            if store.others.contains(where: { $0.id == item.id }),
               let pull = store.detailStore(for: item.repo.id)?.selected, pull.number == item.pull.number {
                store.noteDetail(pull, for: item.id)
            }
            if ReviewDetailState.leftOpen(from: old, to: new) {
                Task { await store.reload(repoKey: item.repo.id) }
            }
        }
        .onChange(of: appState.ui.connectAccountRequest == nil) { _, closed in
            guard closed else { return }
            // An account may have just been connected again.
            let detailNeedsToken = store.selectedItem.flatMap { store.detailStore(for: $0.repo.id) }?.requiresToken == true
            guard !store.accountsNeedingAttention.isEmpty || detailNeedsToken else { return }
            Task {
                await store.refresh(force: true)
                if detailNeedsToken, let item = store.selectedItem { await store.open(item) }
            }
        }
    }

    private var splitLayout: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ReviewsList(store: store) { item in store.selectedID = item.id }
                    .frame(width: geo.size.width >= 1000 ? 380 : 320)
                Rectangle().fill(theme.colors.separator).frame(width: 1)
                detailColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.colors.bgElevated)
            }
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detailColumn: some View {
        if let item = store.selectedItem, let detail = store.detailStore(for: item.repo.id) {
            if detail.selected?.number == item.pull.number {
                PullRequestDetailView(store: detail, localActions: localActions(for: item), showsRepository: true)
                    // A store per repo: its tasks and sheets start again with it.
                    .id(item.repo.id)
            } else if detail.requiresToken {
                PullsTokenMissingSection(
                    host: detail.host ?? item.repo.host,
                    nounPlural: nounPlural(item.repo.host.provider),
                    reconnect: detail.reconnectAccountId != nil,
                    onConnect: {
                        appState.ui.connectAccountRequest = ConnectAccountRequest(instanceId: detail.connectInstanceId,
                                                                                replacing: detail.reconnectAccountId)
                    },
                    onOpenSettings: { appState.ui.openSettings(at: .accounts) }
                )
            } else if let message = detail.error {
                EmptyState(symbol: "exclamationmark.triangle", title: String(localized: "Couldn't load detail"),
                           subtitle: message) {
                    GFButton(title: String(localized: "Retry")) { Task { await store.open(item) } }
                }
            } else {
                // Getting the account's token before the detail can load.
                ProgressView().controlSize(.small)
            }
        } else if let link = store.openingLink {
            openingPlaceholder(link)
        } else {
            EmptyState(symbol: "arrow.triangle.pull", title: String(localized: "Select a pull request"))
        }
    }

    /// A pasted link's pull request while it's read (R2 Ruling 11).
    private func openingPlaceholder(_ link: PendingLink) -> some View {
        VStack(spacing: Spacing.s8) {
            ProgressView().controlSize(.small)
            Text("Opening \(link.host.repo) \(link.host.provider.reference(link.number))…")
                .textRole(.callout)
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Spacing.s32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// The selection's detail store's pull request, while it's the selection's.
    private var detailState: ReviewDetailState? {
        guard let item = store.selectedItem, let detail = store.detailStore(for: item.repo.id),
              let selected = detail.selected, selected.number == item.pull.number else { return nil }
        return ReviewDetailState(itemID: item.id, state: selected.state, isMerging: detail.isMerging)
    }

    /// The open repository's own local actions for its pull requests (spec
    /// §4.3); for any other repo, one button that clones it or goes to its
    /// clone, where they are.
    private func localActions(for item: InboxPull) -> PullRequestLocalActions {
        switch store.detailAction(for: item) {
        case .local:
            repository?.localActions ?? repoAction(ReviewRepoAction(item.repo), for: item)
        case .repo(let action):
            repoAction(action, for: item)
        }
    }

    private func repoAction(_ action: ReviewRepoAction, for item: InboxPull) -> PullRequestLocalActions {
        switch action {
        case .clone(let url):
            .remote(title: String(localized: "Clone repository…"), systemImage: "square.and.arrow.down") {
                appState.ui.requestClone(CloneRequest(initialURL: url))
            }
        case .openInRepository(let localURL):
            .remote(title: String(localized: "Open in repository"), systemImage: "arrow.right.circle") {
                Task { await appState.openPullRequest(item, inRepositoryAt: localURL) }
            }
        }
    }

    /// As the repository's lists word it: whole phrases per provider.
    private func nounPlural(_ provider: RemoteProvider) -> String {
        provider == .gitlab ? String(localized: "merge requests") : String(localized: "pull requests")
    }
}
