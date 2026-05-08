import SwiftUI
import AppKit

/// `.gf-view-pulls` — pull/merge request list. Reads from GitHub or GitLab
/// based on the active repository's `origin` remote, authenticated with a
/// PAT stored in Keychain. Configure the token in Settings → Remote hosts.
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
            tokenSheet(for: host)
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
            content
        }
    }

    // MARK: Header

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

    // MARK: Body

    @ViewBuilder
    private var content: some View {
        if viewModel.pullRequestsLoading && viewModel.pullRequests.isEmpty {
            loadingPlaceholder
        } else if let message = viewModel.pullRequestsError {
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
        } else if viewModel.pullRequestsHost == nil {
            EmptyState(
                icon: .pr,
                title: "No supported remote detected",
                subtitle: "GitHub and GitLab are supported. Add an `origin` remote pointing to one of them."
            ) { EmptyView() }
        } else if viewModel.pullRequestsRequiresToken {
            tokenMissingState
        } else if viewModel.pullRequests.isEmpty {
            EmptyState(
                icon: .pr,
                title: "No open \(headerTitle.lowercased())",
                subtitle: "When somebody opens one against this repo, it'll show up here."
            ) { EmptyView() }
        } else {
            ScrollView {
                LazyVStack(spacing: DesignTokens.Spacing.md) {
                    ForEach(viewModel.pullRequests) { pr in
                        pullRow(pr)
                    }
                }
                .padding(DesignTokens.Spacing.xxxxl)
            }
        }
    }

    // MARK: Loading placeholder

    private static let placeholderTitles = [
        "Add merge request integration",
        "Resizable diff pane and toolbar pinning",
        "WIP: graph perf experiments",
        "Refactor sidebar redesigned layout",
        "Pull request detail view header",
        "Improve fetch performance and retries",
    ]

    private static let placeholderBranches = [
        "feat/mr-integration",
        "feat/diff-pane",
        "feat/graph-perf",
        "feat/sidebar",
        "feat/pr-detail",
        "feat/fetch-perf",
    ]

    @ViewBuilder
    private var loadingPlaceholder: some View {
        ScrollView {
            LazyVStack(spacing: DesignTokens.Spacing.md) {
                ForEach(0..<6, id: \.self) { index in
                    placeholderRow(index: index)
                }
            }
            .padding(DesignTokens.Spacing.xxxxl)
        }
        .skeleton(true)
    }

    @ViewBuilder
    private func placeholderRow(index: Int) -> some View {
        let title = Self.placeholderTitles[index % Self.placeholderTitles.count]
        let branch = Self.placeholderBranches[index % Self.placeholderBranches.count]

        HStack(spacing: DesignTokens.Spacing.xl) {
            statusBadge(.open)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                HStack(spacing: DesignTokens.Spacing.md) {
                    Text(title)
                        .font(AppFont.sans(13, weight: .medium))
                        .foregroundStyle(theme.palette.fg1)
                        .lineLimit(1)
                    MonoText("#000", dim: true)
                }
                HStack(spacing: DesignTokens.Spacing.sm) {
                    MonoText("@author", dim: true)
                    Text("·").foregroundStyle(theme.palette.fg4)
                    MonoText(branch, dim: true)
                    Text("→").foregroundStyle(theme.palette.fg4)
                    MonoText("main", dim: true)
                    Text("·").foregroundStyle(theme.palette.fg4)
                    MonoText("2h ago", dim: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DesignTokens.Spacing.xxl)
        .padding(.vertical, DesignTokens.Spacing.lg)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
    }

    @ViewBuilder
    private var tokenMissingState: some View {
        if let host = viewModel.pullRequestsHost {
            EmptyState(
                icon: .pr,
                title: "\(host.provider.label) token required",
                subtitle: "No token stored for \(host.host). Add a Personal Access Token to list \(headerTitle.lowercased())."
            ) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    GFButton(title: "Add token…", style: .primary) {
                        tokenDraft = ""
                        tokenError = nil
                        tokenSheetHost = host
                    }
                    GFButton(title: "Open Settings") {
                        appState.workspaceSection = .settings
                    }
                }
            }
        } else {
            EmptyState(
                icon: .pr,
                title: "Token required",
                subtitle: "Add a Personal Access Token in Settings → Remote hosts."
            ) { EmptyView() }
        }
    }

    @ViewBuilder
    private func tokenSheet(for host: RemoteHost) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            Text("\(host.provider.label) token")
                .font(AppFont.sans(14, weight: .semibold))
            Text("Token will be stored in macOS Keychain for \(host.host).")
                .font(AppFont.sans(11))
                .foregroundStyle(theme.palette.fg3)
            Text(scopeHint(for: host.provider))
                .font(AppFont.sans(11))
                .foregroundStyle(theme.palette.fg3)
                .fixedSize(horizontal: false, vertical: true)
            SecureField("ghp_… / glpat_…", text: $tokenDraft)
                .textFieldStyle(.plain)
                .font(AppFont.mono(12, family: theme.monoFont))
                .padding(.horizontal, DesignTokens.Spacing.md)
                .frame(height: DesignTokens.Control.height)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).fill(theme.palette.bg2))
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).stroke(theme.palette.lineStrong, lineWidth: DesignTokens.Stroke.regular))
            if let tokenError {
                Text(tokenError)
                    .font(AppFont.sans(11))
                    .foregroundStyle(theme.palette.del)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                GFButton(title: "Cancel") {
                    tokenSheetHost = nil
                }
                Spacer()
                GFButton(title: "Save", style: .primary) {
                    let value = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let error = RemoteCredentialsStore.shared.setToken(value, for: host.host) {
                        tokenError = error
                    } else {
                        tokenSheetHost = nil
                        Task { await viewModel.loadPullRequests(force: true) }
                    }
                }
                .disabled(tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(DesignTokens.Spacing.huge)
        .frame(width: 460)
        .background(theme.palette.bg1)
        .appTheme(theme)
    }

    /// Heuristic — the error has been mapped to a friendly string already, so
    /// match the prefix the formatter uses rather than the underlying URLError.
    private func isTLSError(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("tls") || lower.contains("certificate") || lower.contains("secure connection")
    }

    private func scopeHint(for provider: RemoteProvider) -> String {
        switch provider {
        case .github: "Required scope: `repo` (private) or `public_repo`."
        case .gitlab: "Required scope: `read_api` (or `api` for write actions)."
        }
    }

    // MARK: Row

    @ViewBuilder
    private func pullRow(_ pr: PullRequest) -> some View {
        Button {
            viewModel.selectPullRequest(pr)
        } label: {
            HStack(spacing: DesignTokens.Spacing.xl) {
                statusBadge(pr.state)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    HStack(spacing: DesignTokens.Spacing.md) {
                        Text(pr.title)
                            .font(AppFont.sans(13, weight: .medium))
                            .foregroundStyle(theme.palette.fg1)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        MonoText("#\(pr.number)", dim: true)
                    }
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        if let author = pr.authorLogin {
                            MonoText("@\(author)", dim: true)
                            Text("·").foregroundStyle(theme.palette.fg4)
                        }
                        MonoText(pr.sourceBranch, dim: true)
                        Text("→").foregroundStyle(theme.palette.fg4)
                        MonoText(pr.targetBranch, dim: true)
                        if let updated = pr.updatedAt {
                            Text("·").foregroundStyle(theme.palette.fg4)
                            MonoText(relativeDate(updated), dim: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let webURL = pr.webURL {
                    Button {
                        NSWorkspace.shared.open(webURL)
                    } label: {
                        Text("Open")
                            .font(AppFont.sans(11))
                            .foregroundStyle(theme.palette.fg2)
                            .padding(.horizontal, DesignTokens.Spacing.md)
                            .frame(height: 22)
                            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).fill(theme.palette.bg2))
                            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
                            .contentShape(.rect(cornerRadius: DesignTokens.Radius.xs))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.xxl)
            .padding(.vertical, DesignTokens.Spacing.lg)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
            .contentShape(.rect(cornerRadius: DesignTokens.Radius.md))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func statusBadge(_ state: PullRequest.State) -> some View {
        let p = theme.palette
        let (label, fg, bg): (String, Color, Color) = {
            switch state {
            case .open:   return ("OPEN",   p.ok,   p.ok.opacity(DesignTokens.Opacity.muted))
            case .merged: return ("MERGED", p.info, p.info.opacity(DesignTokens.Opacity.muted))
            case .closed: return ("CLOSED", p.del,  p.del.opacity(DesignTokens.Opacity.muted))
            case .draft:  return ("DRAFT",  p.fg3,  p.bg3)
            }
        }()
        Text(label)
            .font(AppFont.mono(10, weight: .bold, family: theme.monoFont))
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .foregroundStyle(fg)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).fill(bg))
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

#if DEBUG
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
        .environment(AppState.preview)
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
        .environment(AppState.preview)
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
        .environment(AppState.preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}
#endif
