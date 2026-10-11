import SwiftUI

/// Clone › "My repos" (spec §7.4): the repos of a connected account, with
/// an account picker when there are several. Without a usable account it
/// offers to connect (or reconnect) one. The parent decides what to do with
/// the chosen repo and the account it was listed with.
struct RemoteRepoPicker: View {
    let kind: HostingInstance.Kind
    let onSelect: (RemoteRepoSummary, UUID) -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme
    @State private var model: RemoteRepoListModel?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            if let model {
                content(model)
            }
        }
        .onAppear {
            if model == nil {
                model = RemoteRepoListModel(kind: kind, store: appState.accounts, refresher: appState.tokenRefresher)
            }
        }
        // Back from "Connect account": pick up the new or reconnected account.
        .onChange(of: appState.ui.connectAccountRequest == nil) { _, closed in
            if closed { model?.refreshAccounts() }
        }
        .task(id: model?.loadRequest) {
            if let model, model.state == .idle { await model.load() }
        }
    }

    @ViewBuilder
    private func content(_ model: RemoteRepoListModel) -> some View {
        if case .needsAccount(let instanceId, let replacing) = model.state {
            connectCard(instanceId: instanceId, replacing: replacing)
        } else {
            accountSelector(model)
            searchBar(model)
            listOrEmpty(model)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func accountSelector(_ model: RemoteRepoListModel) -> some View {
        if model.accounts.count > 1 {
            HStack(spacing: DesignTokens.Spacing.md) {
                Text("Account")
                    .font(AppFont.sans(FontSize.sm, weight: .medium))
                    .foregroundStyle(theme.palette.fg3)
                Picker("", selection: Binding(get: { model.selectedAccountId ?? model.accounts[0].id },
                                              set: { model.select($0) })) {
                    ForEach(model.accounts) { account in
                        Text(model.label(for: account)).tag(account.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 320)
                Spacer()
            }
        } else if let only = model.accounts.first {
            HStack(spacing: DesignTokens.Spacing.sm) {
                GFIcon(kind: .cloud, size: DesignTokens.IconSize.xs, stroke: theme.palette.fg3)
                Text(model.label(for: only))
                    .font(AppFont.mono(FontSize.sm, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg2)
            }
        }
    }

    private func searchBar(_ model: RemoteRepoListModel) -> some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            GFIcon(kind: .search, size: DesignTokens.IconSize.sm, stroke: theme.palette.fg3)
            GFTextField(placeholder: "Filter by name or description…", text: Bindable(model).search)
            if model.state == .loading || model.isLoadingMore {
                ProgressView().controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func listOrEmpty(_ model: RemoteRepoListModel) -> some View {
        switch model.state {
        case .failed(let message):
            errorCard(message, model: model)
        case .idle, .loading:
            HStack { Spacer(); ProgressView(); Spacer() }
                .padding(.vertical, DesignTokens.Spacing.xxhuge)
        case .loaded where model.repos.isEmpty:
            Text("No repositories found.")
                .font(AppFont.sans(FontSize.sm))
                .foregroundStyle(theme.palette.fg3)
                .padding(.vertical, DesignTokens.Spacing.xxxl)
        case .loaded, .needsAccount:
            list(model)
        }
    }

    private func list(_ model: RemoteRepoListModel) -> some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            ForEach(model.filtered) { repo in
                row(for: repo, model: model)
            }
            if model.hasMore {
                GFButton(title: model.isLoadingMore ? "Loading…" : "Load more",
                         style: .secondary,
                         disabled: model.isLoadingMore) {
                    Task { await model.loadMore() }
                }
                .padding(.top, DesignTokens.Spacing.xs)
            }
        }
    }

    private func row(for repo: RemoteRepoSummary, model: RemoteRepoListModel) -> some View {
        Button {
            if let accountId = model.selectedAccountId { onSelect(repo, accountId) }
        } label: {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.lg) {
                Image(systemName: repo.isPrivate ? "lock.fill" : "globe")
                    .font(.system(size: FontSize.md, weight: .medium))
                    .foregroundStyle(theme.palette.fg3)
                    .frame(width: DesignTokens.IconSize.md)
                    .accessibilityLabel(repo.isPrivate ? "Private" : "Public")
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(repo.fullName)
                        .font(AppFont.mono(FontSize.md, weight: .medium, family: theme.monoFont))
                        .foregroundStyle(theme.palette.fg1)
                        .lineLimit(1)
                    if let desc = repo.description, !desc.isEmpty {
                        Text(desc)
                            .font(AppFont.sans(FontSize.sm))
                            .foregroundStyle(theme.palette.fg3)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer()
                Text("Clone")
                    .font(AppFont.sans(FontSize.sm, weight: .medium))
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

    private func connectCard(instanceId: UUID?, replacing: UUID?) -> some View {
        card {
            Text(replacing == nil ? "Connect a \(kind.label) account" : "Reconnect your \(kind.label) account")
                .font(AppFont.sans(FontSize.lg, weight: .semibold))
                .foregroundStyle(theme.palette.fg1)
            Text(replacing == nil
                 ? "Sign in to browse the repositories you can clone, and clone them over HTTPS with that account."
                 : "Its token was rejected. Reconnect it to browse your repositories again.")
                .font(AppFont.sans(FontSize.sm))
                .foregroundStyle(theme.palette.fg3)
            GFButton(title: replacing == nil ? "Connect account…" : "Reconnect…", style: .primary) {
                appState.ui.connectAccountRequest = ConnectAccountRequest(instanceId: instanceId, replacing: replacing)
            }
        }
    }

    private func errorCard(_ message: String, model: RemoteRepoListModel) -> some View {
        card {
            HStack(spacing: DesignTokens.Spacing.sm) {
                GFIcon(kind: .x, size: DesignTokens.IconSize.md, stroke: theme.palette.del)
                Text("Couldn't load repositories")
                    .font(AppFont.sans(FontSize.md, weight: .semibold))
                    .foregroundStyle(theme.palette.fg1)
            }
            Text(message)
                .font(AppFont.sans(FontSize.sm))
                .foregroundStyle(theme.palette.fg3)
            GFButton(title: "Retry", style: .secondary) {
                Task { await model.load() }
            }
        }
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md, content: content)
            .padding(DesignTokens.Spacing.xxxl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    RemoteRepoPicker(kind: .github) { _, _ in }
        .padding(DesignTokens.Spacing.huge)
        .frame(width: 600, height: 400)
        .background(theme.palette.bg2)
        .previewAppState(.preview)
        .appTheme(theme)
}
