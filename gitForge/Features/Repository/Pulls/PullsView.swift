import SwiftUI

/// Pull/merge request list. Reads from GitHub or GitLab based on the active
/// repository's `origin` remote, authenticated with a PAT stored in Keychain.
struct PullsView: View {
    let store: PullRequestStore
    /// Integrates the selected PR locally ("Resolve locally"); session-wide
    /// work owned by `RepositoryViewModel`.
    let integrateLocally: () async -> RepositoryViewModel.IntegrationOutcome

    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme

    @State private var tokenSheetHost: RemoteHost?
    @State private var tokenDraft: String = ""
    @State private var tokenError: String?

    var body: some View {
        Group {
            if store.selected != nil {
                PullRequestDetailView(store: store, integrateLocally: integrateLocally)
            } else {
                listLayout
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.bg2)
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

    private var listLayout: some View {
        VStack(spacing: DesignTokens.Spacing.none) {
            PullsContentSection(
                store: store,
                nounPlural: headerTitle.lowercased(),
                onAddToken: presentTokenSheet,
                onOpenSettings: { appState.ui.workspaceSection = .settings }
            )
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await store.load(force: true) } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .help("Refresh pull requests")
                .disabled(store.isLoading)
            }
        }
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
