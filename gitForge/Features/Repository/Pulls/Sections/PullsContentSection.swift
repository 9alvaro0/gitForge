import SwiftUI

/// The PR screen's full-width states: loading / error / no host /
/// missing token. Its only state is the certificate trust
/// flow offered on TLS errors; every other action flows back to the
/// compositor via callbacks.
struct PullsContentSection: View {
    let store: PullRequestStore
    let nounPlural: String
    let onAddToken: () -> Void
    let onOpenSettings: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var trustHost: String?

    var body: some View {
        content
            .trustCertificatePrompt(host: $trustHost) {
                Task { await store.load(force: true) }
            }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading && store.items.isEmpty {
            PullsLoadingPlaceholder()
        } else if let message = store.error {
            errorState(message: message)
        } else if store.host == nil {
            EmptyState(
                icon: .pr,
                title: "No supported remote detected",
                subtitle: "GitHub and GitLab are supported. Add an `origin` remote pointing to one of them."
            )
        } else if store.requiresToken {
            PullsTokenMissingSection(
                host: store.host,
                nounPlural: nounPlural,
                onAddToken: onAddToken,
                onOpenSettings: onOpenSettings
            )
        }
        // Loaded with a host and token: `PullsView` shows the list instead.
    }

    private func errorState(message: String) -> some View {
        EmptyState(icon: .warn, title: "Couldn't load", subtitle: message) {
            HStack(spacing: Spacing.s8) {
                if isTLSError(message), let host = store.host {
                    GFButton(title: "Trust \(host.host)…", style: .primary) {
                        trustHost = host.host
                    }
                    GFButton(title: "Try again") {
                        Task { await store.load(force: true) }
                    }
                } else {
                    GFButton(title: "Try again", style: .primary) {
                        Task { await store.load(force: true) }
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

#Preview("List") {
    @Previewable @State var theme = AppTheme()
    PullsContentSection(
        store: .previewWithPullRequests,
        nounPlural: "pull requests",
        onAddToken: {}, onOpenSettings: {}
    )
    .frame(width: 1100, height: 600)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}

#Preview("Token missing") {
    @Previewable @State var theme = AppTheme()
    let store: PullRequestStore = {
        let s = PullRequestStore.previewWithPullRequests
        s.requiresToken = true
        return s
    }()
    PullsContentSection(
        store: store,
        nounPlural: "pull requests",
        onAddToken: {}, onOpenSettings: {}
    )
    .frame(width: 1100, height: 600)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}

