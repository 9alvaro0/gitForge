import SwiftUI

/// Pull/merge request list. Reads from GitHub or GitLab based on the active
/// repository's `origin` remote, authenticated with a PAT stored in Keychain.
struct PullsView: View {
    let store: PullRequestStore
    /// Integrates the selected PR locally ("Resolve locally"); session-wide
    /// work owned by `RepositoryViewModel`.
    let integrateLocally: () async -> RepositoryViewModel.IntegrationOutcome
    /// Fetches and checks out the selected PR's branch.
    var checkoutBranch: () async -> Result<String, Error> = { .failure(PullCheckoutError.noSelection) }

    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme

    @State private var tokenSheetHost: RemoteHost?
    @State private var tokenDraft: String = ""
    @State private var tokenError: String?

    var body: some View {
        Group {
            if listReady {
                splitLayout
            } else {
                PullsContentSection(
                    store: store,
                    nounPlural: headerTitle.lowercased(),
                    onAddToken: presentTokenSheet,
                    onOpenSettings: { appState.ui.workspaceSection = .settings }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.colors.bgContent)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await store.load(force: true) } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .help("Refresh \(headerTitle.lowercased())")
                .disabled(store.isLoading)
            }
        }
        .navigationTitle(headerTitle)
        .task { await store.load() }
        .sheet(item: $tokenSheetHost) { host in
            PullsTokenSheet(
                host: host,
                draft: $tokenDraft,
                error: $tokenError,
                onCancel: { tokenSheetHost = nil },
                onSave: { saveToken(for: host) }
            )
        }
    }

    /// The list (and its detail) shows once the host, the token and a first
    /// load are in; before that the full-width states take over.
    private var listReady: Bool {
        store.host != nil && !store.requiresToken && store.error == nil && !(store.isLoading && store.items.isEmpty)
    }

    private var splitLayout: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    scopeBar
                    list
                }
                .frame(width: geo.size.width >= 1000 ? 380 : 320)
                Rectangle().fill(theme.colors.separator).frame(width: 1)
                Group {
                    if store.selected != nil {
                        PullRequestDetailView(store: store, integrateLocally: integrateLocally, checkoutBranch: checkoutBranch)
                    } else {
                        EmptyState(icon: .pr, title: "Select a \(singularNoun)")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.colors.bgElevated)
            }
        }
        // Open the first PR so the detail isn't blank on arrival.
        .task(id: store.visibleItems.map(\.id)) {
            if store.selected == nil || !store.visibleItems.contains(where: { $0.id == store.selected?.id }),
               let first = store.visibleItems.first {
                store.select(first)
            }
        }
    }

    /// Above the list rather than in the toolbar, where it fell into `»`.
    private var scopeBar: some View {
        HStack {
            SegmentedControl<PullListScope>(
                PullListScope.allCases.map { scope in
                    (scope, store.count(for: scope).map { "\(scope.title) \($0)" } ?? scope.title)
                },
                selection: Binding(get: { store.scope }, set: { scope in Task { await store.setScope(scope) } })
            )
            .fixedSize()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.s12)
        .frame(height: 44)
    }

    @ViewBuilder
    private var list: some View {
        let items = store.visibleItems
        if items.isEmpty {
            if store.scope == .closed && !store.closedLoaded {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyState(icon: .pr, title: emptyTitle)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: Spacing.s2) {
                    ForEach(items) { pr in
                        PullRequestRow(
                            pullRequest: pr,
                            hostLabel: store.host?.provider.label,
                            ci: store.ciStatus(for: pr),
                            isSelected: store.selected?.id == pr.id,
                            onSelect: { store.select(pr) }
                        )
                    }
                }
                .padding(.horizontal, Spacing.s8)
                .padding(.bottom, Spacing.s8)
            }
        }
    }

    private var emptyTitle: String {
        switch store.scope {
        case .open: "No open \(headerTitle.lowercased())"
        case .mine: "None of the open \(headerTitle.lowercased()) are yours"
        case .closed: "No closed \(headerTitle.lowercased())"
        }
    }

    private var singularNoun: String {
        store.host?.provider.pullNoun.lowercased() ?? "pull request"
    }

    private var headerTitle: String {
        store.host?.provider.pullNoun.appending("s") ?? "Pull requests"
    }


    private func presentTokenSheet() {
        tokenDraft = ""
        tokenError = nil
        tokenSheetHost = store.host
    }

    private func saveToken(for host: RemoteHost) {
        let value = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = RemoteCredentialsStore.shared.setToken(value, for: host.host) {
            tokenError = error
        } else {
            tokenSheetHost = nil
            Task { await store.load(force: true) }
        }
    }
}

#Preview("Loaded") {
    @Previewable @State var theme = AppTheme()
    PullsView(store: .previewWithPullRequests, integrateLocally: { .clean })
        .previewAppState(.preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}

#Preview("Loading") {
    @Previewable @State var theme = AppTheme()
    let store: PullRequestStore = {
        let s = PullRequestStore.previewWithPullRequests
        s.items = []
        s.isLoading = true
        return s
    }()
    PullsView(store: store, integrateLocally: { .clean })
        .previewAppState(.preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}

#Preview("Token missing") {
    @Previewable @State var theme = AppTheme()
    let store: PullRequestStore = {
        let s = PullRequestStore.preview
        s.host = .previewGitLab
        s.requiresToken = true
        return s
    }()
    PullsView(store: store, integrateLocally: { .clean })
        .previewAppState(.preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}
