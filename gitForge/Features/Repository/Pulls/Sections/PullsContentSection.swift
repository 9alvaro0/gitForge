import SwiftUI

/// Switch over the various PR list states (loading / error / no host /
/// missing-token / empty / list). Owns no state of its own — every action
/// flows back to the compositor via callbacks.
struct PullsContentSection: View {
    @Bindable var viewModel: RepositoryViewModel
    let nounPlural: String
    let onAddToken: () -> Void
    let onOpenSettings: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        if viewModel.pullRequestsLoading && viewModel.pullRequests.isEmpty {
            PullsLoadingPlaceholder()
        } else if let message = viewModel.pullRequestsError {
            errorState(message: message)
        } else if viewModel.pullRequestsHost == nil {
            EmptyState(
                icon: .pr,
                title: "No supported remote detected",
                subtitle: "GitHub and GitLab are supported. Add an `origin` remote pointing to one of them."
            ) { EmptyView() }
        } else if viewModel.pullRequestsRequiresToken {
            PullsTokenMissingSection(
                host: viewModel.pullRequestsHost,
                nounPlural: nounPlural,
                onAddToken: onAddToken,
                onOpenSettings: onOpenSettings
            )
        } else if viewModel.pullRequests.isEmpty {
            EmptyState(
                icon: .pr,
                title: "No open \(nounPlural)",
                subtitle: "When somebody opens one against this repo, it'll show up here."
            ) { EmptyView() }
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: DesignTokens.Spacing.md) {
                ForEach(viewModel.pullRequests) { pr in
                    PullRequestRow(pullRequest: pr) {
                        viewModel.selectPullRequest(pr)
                    }
                }
            }
            .padding(DesignTokens.Spacing.xxxxl)
        }
    }

    private func errorState(message: String) -> some View {
        EmptyState(icon: .warn, title: "Couldn't load", subtitle: message) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                if isTLSError(message), let host = viewModel.pullRequestsHost {
                    GFButton(title: "Trust \(host.host)", style: .primary) {
                        RemoteHostTrust.shared.setTrusted(host.host, true)
                        Task { await viewModel.loadPullRequests(force: true) }
                    }
                    GFButton(title: "Try again") {
                        Task { await viewModel.loadPullRequests(force: true) }
                    }
                } else {
                    GFButton(title: "Try again", style: .primary) {
                        Task { await viewModel.loadPullRequests(force: true) }
                    }
                }
            }
        }
    }

    /// The error has been mapped to a friendly string already, so match the
    /// prefix the formatter uses rather than the underlying URLError.
    private func isTLSError(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("tls") || lower.contains("certificate") || lower.contains("secure connection")
    }
}
