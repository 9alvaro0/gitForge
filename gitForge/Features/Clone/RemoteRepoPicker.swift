import SwiftUI

/// Lists repos the current user has access to on a remote host (GitHub or
/// GitLab) using the PAT stored in `RemoteCredentialsStore`. Renders a search
/// box + scrollable list with paginated loading. The parent decides what to do
/// when a repo is selected — typically: prefill the clone form's URL/path and
/// kick off the clone.
struct RemoteRepoPicker: View {
    let provider: RemoteProvider
    /// Hosts the user has tokens for that match this provider, plus the
    /// canonical default (`github.com` / `gitlab.com`). First element is the
    /// initial selection.
    let availableHosts: [String]
    let onSelect: (RemoteRepoSummary) -> Void

    @Environment(\.appTheme) private var theme

    @State private var host: String = ""
    @State private var repos: [RemoteRepoSummary] = []
    @State private var search: String = ""
    @State private var page: Int = 1
    @State private var hasMore: Bool = true
    @State private var loading: Bool = false
    @State private var loadingMore: Bool = false
    @State private var loadError: String?
    @State private var hasLoadedOnce: Bool = false

    private var token: String? {
        RemoteCredentialsStore.shared.token(for: host)
    }

    private var filtered: [RemoteRepoSummary] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return repos }
        return repos.filter {
            $0.fullName.lowercased().contains(q)
                || $0.name.lowercased().contains(q)
                || ($0.description?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            hostSelector
            if token == nil {
                missingTokenCard
            } else {
                searchBar
                listOrEmpty
            }
        }
        .onAppear {
            if host.isEmpty { host = availableHosts.first ?? "" }
        }
        .onChange(of: host) { _, _ in
            // Switching hosts wipes state — different API, different repos.
            hasLoadedOnce = false
            page = 1
            hasMore = true
            repos = []
            loadError = nil
        }
        .task(id: host) { await loadInitialIfNeeded() }
    }

    // MARK: - Sections

    @ViewBuilder
    private var hostSelector: some View {
        if availableHosts.count > 1 {
            HStack(spacing: DesignTokens.Spacing.md) {
                Text("Host")
                    .font(AppFont.sans(11, weight: .medium))
                    .foregroundStyle(theme.palette.fg3)
                Picker("", selection: $host) {
                    ForEach(availableHosts, id: \.self) { h in
                        Text(h).tag(h)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 280)
                Spacer()
            }
        } else if let only = availableHosts.first {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "network")
                    .font(.system(size: FontSize.caption, weight: .medium))
                    .foregroundStyle(theme.palette.fg3)
                Text(only)
                    .font(AppFont.mono(11, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg2)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: FontSize.footnote, weight: .medium))
                .foregroundStyle(theme.palette.fg3)
            GFTextField(placeholder: "Filter by name or description…", text: $search)
            if loading || loadingMore {
                ProgressView().controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var listOrEmpty: some View {
        if let loadError, repos.isEmpty {
            errorCard(loadError)
        } else if !hasLoadedOnce && repos.isEmpty {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding(.vertical, DesignTokens.Spacing.xxhuge)
        } else if repos.isEmpty {
            emptyCard
        } else {
            list
        }
    }

    private var list: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            ForEach(filtered) { repo in
                row(for: repo)
            }
            if hasMore {
                GFButton(title: loadingMore ? "Loading…" : "Load more",
                         style: .secondary,
                         disabled: loadingMore) {
                    Task { await loadMore() }
                }
                .padding(.top, DesignTokens.Spacing.xs)
            }
        }
    }

    private func row(for repo: RemoteRepoSummary) -> some View {
        Button {
            onSelect(repo)
        } label: {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.lg) {
                Image(systemName: repo.isPrivate ? "lock.fill" : "globe")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.palette.fg3)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(repo.fullName)
                        .font(AppFont.mono(12, weight: .medium, family: theme.monoFont))
                        .foregroundStyle(theme.palette.fg1)
                        .lineLimit(1)
                    if let desc = repo.description, !desc.isEmpty {
                        Text(desc)
                            .font(AppFont.sans(11))
                            .foregroundStyle(theme.palette.fg3)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer()
                Text("Clone")
                    .font(AppFont.sans(11, weight: .medium))
                    .foregroundStyle(theme.palette.accent)
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.vertical, DesignTokens.Spacing.lg)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
            .contentShape(.rect(cornerRadius: DesignTokens.Radius.md))
        }
        .buttonStyle(.plain)
    }

    private var missingTokenCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("No token configured for \(host.isEmpty ? provider.label : host)")
                .font(AppFont.sans(13, weight: .semibold))
                .foregroundStyle(theme.palette.fg1)
            Text("Add a Personal Access Token in Settings → Remote hosts to browse your repos from this host.")
                .font(AppFont.sans(11))
                .foregroundStyle(theme.palette.fg3)
        }
        .padding(DesignTokens.Spacing.xxxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
    }

    private var emptyCard: some View {
        Text("No repositories found.")
            .font(AppFont.sans(11))
            .foregroundStyle(theme.palette.fg3)
            .padding(.vertical, DesignTokens.Spacing.xxxl)
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(theme.palette.del)
                Text("Couldn't load repos from \(host)")
                    .font(AppFont.sans(12, weight: .semibold))
                    .foregroundStyle(theme.palette.fg1)
            }
            Text(message)
                .font(AppFont.sans(11))
                .foregroundStyle(theme.palette.fg3)
            // Tokens are saved per-host; if the user landed on the wrong host
            // the message above won't help. Nudge them to the right place.
            if availableHosts.count > 1 {
                Text("Try a different host above, or check the token's scopes in Settings.")
                    .font(AppFont.sans(11))
                    .foregroundStyle(theme.palette.fg3)
            } else {
                Text("Check the token's scopes in Settings (needs read access to repositories), or that the token is for this host.")
                    .font(AppFont.sans(11))
                    .foregroundStyle(theme.palette.fg3)
            }
            GFButton(title: "Retry", style: .secondary) {
                Task { await retry() }
            }
        }
        .padding(DesignTokens.Spacing.xxxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
    }

    // MARK: - Loading

    private func loadInitialIfNeeded() async {
        guard !hasLoadedOnce, !loading, token != nil else { return }
        await loadPage(1, replacing: true)
        hasLoadedOnce = true
    }

    private func retry() async {
        loadError = nil
        hasLoadedOnce = false
        page = 1
        hasMore = true
        repos = []
        await loadPage(1, replacing: true)
        hasLoadedOnce = true
    }

    private func loadMore() async {
        guard hasMore, !loadingMore, !loading else { return }
        await loadPage(page + 1, replacing: false)
    }

    private func loadPage(_ pageNumber: Int, replacing: Bool) async {
        guard let token else { return }
        let browser = RemoteRepoBrowserFactory.make(for: provider)

        if replacing { loading = true } else { loadingMore = true }
        defer {
            if replacing { loading = false } else { loadingMore = false }
        }

        do {
            let chunk = try await browser.fetchUserRepos(host: host, token: token, page: pageNumber)
            if replacing {
                repos = chunk
            } else {
                repos.append(contentsOf: chunk)
            }
            page = pageNumber
            hasMore = chunk.count >= 50
            loadError = nil
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            loadError = message
        }
    }
}

#Preview("No token") {
    @Previewable @State var theme = AppTheme()
    RemoteRepoPicker(provider: .github, availableHosts: ["github.com"]) { _ in }
        .padding(DesignTokens.Spacing.huge)
        .frame(width: 600, height: 400)
        .background(theme.palette.bg2)
        .appTheme(theme)
}

#Preview("Multi-host") {
    @Previewable @State var theme = AppTheme()
    RemoteRepoPicker(provider: .gitlab, availableHosts: ["gitlab.com", "gitlab.example.com"]) { _ in }
        .padding(DesignTokens.Spacing.huge)
        .frame(width: 600, height: 400)
        .background(theme.palette.bg2)
        .appTheme(theme)
}
