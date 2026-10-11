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
        VStack(alignment: .leading, spacing: Spacing.s12) {
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
            HStack(spacing: Spacing.s8) {
                Text("Account")
                    .textRole(.callout, weight: .medium)
                    .foregroundStyle(theme.colors.textTertiary)
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
            HStack(spacing: Spacing.s6) {
                Image(systemName: "cloud").font(.system(size: 11)).foregroundStyle(theme.colors.textTertiary).accessibilityHidden(true)
                Text(model.label(for: only))
                    .textRole(.monoSmall)
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
    }

    private func searchBar(_ model: RemoteRepoListModel) -> some View {
        HStack(spacing: Spacing.s8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(theme.colors.textTertiary).accessibilityHidden(true)
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
                .padding(.vertical, Spacing.s32)
        case .loaded where model.repos.isEmpty:
            Text("No repositories found.")
                .textRole(.callout)
                .foregroundStyle(theme.colors.textTertiary)
                .padding(.vertical, Spacing.s16)
        case .loaded, .needsAccount:
            list(model)
        }
    }

    private func list(_ model: RemoteRepoListModel) -> some View {
        VStack(spacing: Spacing.s6) {
            ForEach(model.filtered) { repo in
                row(for: repo, model: model)
            }
            if model.hasMore {
                GFButton(title: model.isLoadingMore ? "Loading…" : "Load more",
                         style: .secondary,
                         disabled: model.isLoadingMore) {
                    Task { await model.loadMore() }
                }
                .padding(.top, Spacing.s4)
            }
        }
    }

    private func row(for repo: RemoteRepoSummary, model: RemoteRepoListModel) -> some View {
        Button {
            if let accountId = model.selectedAccountId { onSelect(repo, accountId) }
        } label: {
            HStack(alignment: .top, spacing: Spacing.s12) {
                Image(systemName: repo.isPrivate ? "lock.fill" : "globe")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 16)
                    .accessibilityLabel(repo.isPrivate ? "Private" : "Public")
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    Text(repo.fullName)
                        .textRole(.mono, weight: .medium)
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(1)
                    if let desc = repo.description, !desc.isEmpty {
                        Text(desc)
                            .textRole(.callout)
                            .foregroundStyle(theme.colors.textTertiary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer()
                Text("Clone")
                    .textRole(.callout, weight: .medium)
                    .foregroundStyle(theme.colors.accent)
            }
            .padding(.horizontal, Spacing.s12)
            .padding(.vertical, Spacing.s12)
            .background(RoundedRectangle(cornerRadius: Radius.card).fill(theme.colors.bgElevated))
            .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(theme.colors.separator, lineWidth: 1))
            .contentShape(.rect(cornerRadius: Radius.card))
        }
        .buttonStyle(.plain)
    }

    private func connectCard(instanceId: UUID?, replacing: UUID?) -> some View {
        card {
            Text(replacing == nil ? "Connect a \(kind.label) account" : "Reconnect your \(kind.label) account")
                .textRole(.headline)
                .foregroundStyle(theme.colors.textPrimary)
            Text(replacing == nil
                 ? "Sign in to browse the repositories you can clone, and clone them over HTTPS with that account."
                 : "Its token was rejected. Reconnect it to browse your repositories again.")
                .textRole(.callout)
                .foregroundStyle(theme.colors.textTertiary)
            GFButton(title: replacing == nil ? "Connect account…" : "Reconnect…", style: .primary) {
                appState.ui.connectAccountRequest = ConnectAccountRequest(instanceId: instanceId, replacing: replacing)
            }
        }
    }

    private func errorCard(_ message: String, model: RemoteRepoListModel) -> some View {
        card {
            HStack(spacing: Spacing.s6) {
                Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(theme.colors.del).accessibilityHidden(true)
                Text("Couldn't load repositories")
                    .textRole(.body, weight: .semibold)
                    .foregroundStyle(theme.colors.textPrimary)
            }
            Text(message)
                .textRole(.callout)
                .foregroundStyle(theme.colors.textTertiary)
            GFButton(title: "Retry", style: .secondary) {
                Task { await model.load() }
            }
        }
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s8, content: content)
            .padding(Spacing.s16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.card).fill(theme.colors.bgElevated))
            .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(theme.colors.separator, lineWidth: 1))
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    RemoteRepoPicker(kind: .github) { _, _ in }
        .padding(Spacing.s24)
        .frame(width: 600, height: 400)
        .background(theme.colors.bgContent)
        .previewAppState(.preview)
        .appTheme(theme)
}
