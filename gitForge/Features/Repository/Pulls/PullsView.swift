import SwiftUI

/// Pull/merge request list. Reads from GitHub or GitLab based on the active
/// repository's `origin` remote, authenticated with a PAT stored in Keychain.
struct PullsView: View {
    @Bindable var viewModel: RepositoryViewModel

    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme

    @State private var tokenSheetHost: RemoteHost?
    @State private var tokenDraft: String = ""
    @State private var tokenError: String?

    var body: some View {
        Group {
            if viewModel.selectedPullRequest != nil {
                PullRequestDetailView(viewModel: viewModel)
            } else {
                listLayout
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.bg2)
        .task { await viewModel.loadPullRequests() }
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
            ContentHeader(title: headerTitle) {
                subtitle
            } right: {
                ToolButton(.fetch, label: "Refresh", disabled: viewModel.pullRequestsLoading) {
                    Task { await viewModel.loadPullRequests(force: true) }
                }
            }
            PullsContentSection(
                viewModel: viewModel,
                nounPlural: headerTitle.lowercased(),
                onAddToken: presentTokenSheet,
                onOpenSettings: { appState.ui.workspaceSection = .settings }
            )
        }
    }

    private var headerTitle: String {
        viewModel.pullRequestsHost?.provider.pullNoun.appending("s") ?? "Pull requests"
    }

    @ViewBuilder
    private var subtitle: some View {
        if let host = viewModel.pullRequestsHost {
            MonoText("\(host.slug) · \(host.provider.label.lowercased())", dim: true)
        } else {
            MonoText("not connected", dim: true)
        }
    }

    private func presentTokenSheet() {
        tokenDraft = ""
        tokenError = nil
        tokenSheetHost = viewModel.pullRequestsHost
    }

    private func saveToken(for host: RemoteHost) {
        let value = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = RemoteCredentialsStore.shared.setToken(value, for: host.host) {
            tokenError = error
        } else {
            tokenSheetHost = nil
            Task { await viewModel.loadPullRequests(force: true) }
        }
    }
}

#Preview("Loaded") {
    @Previewable @State var theme = AppTheme()
    let vm: RepositoryViewModel = {
        let v = RepositoryViewModel.preview
        v.pullRequests = PullRequest.previewSamples
        v.pullRequestsHost = RemoteHost(
            provider: .github, host: "github.com", owner: "9alvaro0", repo: "gitForge"
        )
        return v
    }()
    PullsView(viewModel: vm)
        .previewAppState(.preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}

#Preview("Loading") {
    @Previewable @State var theme = AppTheme()
    let vm: RepositoryViewModel = {
        let v = RepositoryViewModel.preview
        v.pullRequestsLoading = true
        v.pullRequestsHost = RemoteHost(
            provider: .github, host: "github.com", owner: "9alvaro0", repo: "gitForge"
        )
        return v
    }()
    PullsView(viewModel: vm)
        .previewAppState(.preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}

#Preview("Token missing") {
    @Previewable @State var theme = AppTheme()
    let vm: RepositoryViewModel = {
        let v = RepositoryViewModel.preview
        v.pullRequestsHost = RemoteHost(
            provider: .gitlab, host: "gitlab.com", owner: "group", repo: "project"
        )
        v.pullRequestsRequiresToken = true
        return v
    }()
    PullsView(viewModel: vm)
        .previewAppState(.preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}
