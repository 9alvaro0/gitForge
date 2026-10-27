import SwiftUI

/// Open and Closed (U1 Ruling 8): the open repository's own pull or merge
/// requests, read from its `origin` with the repo's hosting account, and the
/// selected one's detail with the repository's local actions. Until the host,
/// the token and a first load are in, the full-width states of
/// `PullsContentSection` take their place. The tab bar above picks the list
/// (`PullRequestStore.scope`).
struct PullsRepositoryPane: View {
    let repository: PullsRepository

    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme

    private var store: PullRequestStore { repository.store }

    var body: some View {
        Group {
            if store.isListReady {
                splitLayout
            } else {
                PullsContentSection(
                    store: store,
                    nounPlural: nounPlural,
                    onConnect: {
                        appState.ui.connectAccountRequest = ConnectAccountRequest(instanceId: store.connectInstanceId,
                                                                                replacing: store.reconnectAccountId)
                    },
                    onAddInstance: { suggestion in
                        appState.ui.addInstanceRequest = AddInstanceRequest(kind: suggestion.kind, url: "https://\(suggestion.host)")
                    },
                    onOpenSettings: { appState.ui.openSettings(at: .accounts) }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: appState.ui.connectAccountRequest == nil) { _, closed in
            // Also from an error: the right account may have just been connected.
            if closed, store.requiresToken || store.error != nil { Task { await store.load(force: true) } }
        }
        .onChange(of: appState.ui.addInstanceRequest == nil) { _, closed in
            if closed, store.host == nil { Task { await store.load(force: true) } }
        }
    }

    private var splitLayout: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                list
                    .frame(width: geo.size.width >= 1000 ? 380 : 320)
                Rectangle().fill(theme.colors.separator).frame(width: 1)
                Group {
                    if store.selected != nil {
                        PullRequestDetailView(store: store, localActions: repository.localActions)
                    } else {
                        EmptyState(symbol: "arrow.triangle.pull", title: selectTitle)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.colors.bgElevated)
            }
        }
        // Open the first PR so the detail isn't blank on arrival (a PR just
        // merged here stays open though it left the list).
        .task(id: store.visibleItems.map(\.id)) {
            if let next = store.pullToAutoSelect() { store.select(next) }
        }
    }

    @ViewBuilder
    private var list: some View {
        let items = store.visibleItems
        if items.isEmpty {
            if store.scope == .closed && !store.closedLoaded {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyState(symbol: "arrow.triangle.pull", title: emptyTitle)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: Spacing.s2) {
                    ForEach(items) { pr in
                        PullRequestRow(
                            pullRequest: pr,
                            hostLabel: nil,
                            reference: store.host?.provider.reference(pr.number),
                            ci: store.ciStatus(for: pr),
                            isSelected: store.selected?.id == pr.id,
                            actions: actions(for: pr),
                            onSelect: { store.select(pr) }
                        )
                    }
                }
                .padding(.horizontal, Spacing.s8)
                // Off the tab bar's rule at the top: a selected row's fill
                // would touch it.
                .padding(.vertical, Spacing.s8)
            }
        }
    }

    /// A row's shortcuts: Approve on someone else's pull request, Merge on
    /// one the host says is ready.
    private func actions(for pr: PullRequest) -> PullRowActions {
        let reviewable = (pr.state == .open || pr.state == .draft)
            && (store.currentUser == nil || pr.authorLogin != store.currentUser)
        return PullRowActions(
            approve: reviewable ? { store.requestQuickAction(.approve, on: pr) } : nil,
            merge: pr.isReadyToMerge ? { store.requestQuickAction(.merge, on: pr) } : nil
        )
    }

    // Whole phrases per provider ("pull request" on GitHub and by default,
    // "merge request" on GitLab) so translations needn't splice nouns.

    private var isMergeRequest: Bool { store.host?.provider == .gitlab }

    private var emptyTitle: String {
        switch store.scope {
        case .open:
            isMergeRequest ? String(localized: "No open merge requests") : String(localized: "No open pull requests")
        case .closed:
            isMergeRequest ? String(localized: "No closed merge requests") : String(localized: "No closed pull requests")
        }
    }

    private var selectTitle: String {
        isMergeRequest ? String(localized: "Select a merge request") : String(localized: "Select a pull request")
    }

    /// Lowercase plural noun spliced into the full-width states' sentences.
    private var nounPlural: String {
        isMergeRequest ? String(localized: "merge requests") : String(localized: "pull requests")
    }
}

extension PullRequestStore {
    /// The list (and its detail) shows once the host, the token and a first
    /// load are in; before that the full-width states of `PullsContentSection`
    /// take Open and Closed over, and their tabs show no number.
    var isListReady: Bool {
        host != nil && !requiresToken && !accountNotChosen && error == nil && !(isLoading && items.isEmpty)
    }
}
