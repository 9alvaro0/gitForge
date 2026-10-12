import SwiftUI

/// Settings › Accounts (P4 spec §5.1): one block per instance, one row per
/// account, with the main action visible and the rest in a menu.
struct AccountsSection: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppState.self) private var appState

    @State private var trustHost: String?
    @State private var trustedHosts: Set<String> = []
    @State private var clientIdInstance: HostingInstance?
    @State private var clientIdDraft = ""
    @State private var disconnecting: AccountRowModel?
    @State private var removingInstance: InstanceBlockModel?

    private var store: AccountStore { appState.accounts }

    private var blocks: [InstanceBlockModel] {
        AccountsSettingsModel.blocks(instances: store.instances, accounts: store.accounts,
                                     copiedAccountIds: Set(store.legacyHostAccounts.values),
                                     trustedHosts: trustedHosts, now: .now)
    }

    var body: some View {
        SettingsSection(title: "Accounts", subtitle: "Sign in to GitHub and GitLab to push over HTTPS and work with pull requests.") {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                if index > 0 { SettingsDivider() }
                instanceBlock(block)
            }
            let otherTrusted = AccountsSettingsModel.otherTrustedHosts(trustedHosts, instances: store.instances)
            if !otherTrusted.isEmpty {
                SettingsDivider()
                otherTrustedBlock(otherTrusted)
            }
            SettingsDivider()
            HStack(spacing: Spacing.s8) {
                GFButton(title: "Connect account…", style: .primary, size: .small) {
                    appState.ui.connectAccountRequest = ConnectAccountRequest()
                }
                GFButton(title: "Add instance…", size: .small) { appState.ui.addInstanceRequest = AddInstanceRequest() }
                Spacer()
            }
            .padding(Spacing.s12)
        }
        .onAppear { trustedHosts = Set(RemoteHostTrust.shared.trustedHosts()) }
        .trustCertificatePrompt(host: $trustHost) { trustedHosts = Set(RemoteHostTrust.shared.trustedHosts()) }
        .sheet(item: $clientIdInstance) { instance in clientIdSheet(instance) }
        .confirmationDialog("Disconnect \(disconnecting?.title ?? "")?", isPresented: $disconnecting.isPresent(),
                            presenting: disconnecting) { row in
            Button("Disconnect", role: .destructive) { store.removeAccount(row.id) }
        } message: { _ in
            Text("gitForge forgets this account and its token, and repositories that used it go back to automatic.")
        }
        .confirmationDialog("Remove \(removingInstance?.host ?? "")?", isPresented: $removingInstance.isPresent(),
                            presenting: removingInstance) { block in
            Button("Remove", role: .destructive) { store.removeInstance(block.id) }
        } message: { block in
            Text(block.accounts.isEmpty ? "The instance is removed from gitForge."
                 : "Its \(block.accounts.count) account(s) are disconnected too.")
        }
    }

    private func otherTrustedBlock(_ hosts: [String]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s6) {
            Text("Other trusted certificates").textRole(.body, weight: .semibold).foregroundStyle(theme.colors.textPrimary)
            ForEach(hosts, id: \.self) { host in
                HStack(spacing: Spacing.s8) {
                    MonoText(host, dim: true)
                    Spacer()
                    GFButton(title: "Stop trusting", size: .small) {
                        RemoteHostTrust.shared.revoke(host)
                        trustedHosts = Set(RemoteHostTrust.shared.trustedHosts())
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.s12).padding(.vertical, Spacing.s8)
    }

    @ViewBuilder
    private func instanceBlock(_ block: InstanceBlockModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.s8) {
                Text(block.providerLabel).textRole(.body, weight: .semibold).foregroundStyle(theme.colors.textPrimary)
                MonoText(block.host, dim: true)
                tag(block.tag)
                Spacer()
                Menu {
                    if block.isTrusted {
                        Button("Stop trusting certificate") {
                            RemoteHostTrust.shared.revoke(block.host)
                            trustedHosts = Set(RemoteHostTrust.shared.trustedHosts())
                        }
                    } else {
                        Button("Trust certificate…") { trustHost = block.host }
                    }
                    if !block.isBuiltIn {
                        Button("OAuth client ID…") {
                            clientIdInstance = store.instances.first { $0.id == block.id }
                            clientIdDraft = clientIdInstance?.oauthClientId ?? ""
                        }
                        Divider()
                        Button("Remove instance…", role: .destructive) { removingInstance = block }
                    }
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.plain).fixedSize()
                .help("Instance options")
            }
            .padding(.horizontal, Spacing.s12).padding(.vertical, Spacing.s8)

            if block.accounts.isEmpty {
                HStack {
                    Text("No accounts. Connect one to push over HTTPS and see pull requests.")
                        .textRole(.callout).foregroundStyle(theme.colors.textTertiary)
                    Spacer()
                    GFButton(title: "Connect…", size: .small) {
                        appState.ui.connectAccountRequest = ConnectAccountRequest(instanceId: block.id)
                    }
                }
                .padding(.horizontal, Spacing.s12).padding(.bottom, Spacing.s8)
            }
            ForEach(block.accounts) { row in
                accountRow(row, instanceId: block.id)
            }
        }
    }

    private func accountRow(_ row: AccountRowModel, instanceId: UUID) -> some View {
        HStack(spacing: Spacing.s8) {
            AccountAvatar(initials: row.initials, url: row.avatarURL)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).textRole(.body, weight: .medium).foregroundStyle(theme.colors.textPrimary)
                Text(row.subtitle).textRole(.caption).foregroundStyle(theme.colors.textTertiary).lineLimit(1)
            }
            Spacer(minLength: Spacing.s8)
            statusPill(row)
            switch row.primaryAction {
            case .reconnect?:
                GFButton(title: "Reconnect…", size: .small) {
                    appState.ui.connectAccountRequest = ConnectAccountRequest(instanceId: instanceId, replacing: row.id)
                }
            case .test?:
                GFButton(title: "Test", size: .small) { test(row) }
            case nil:
                EmptyView()
            }
            Menu {
                Button("Reconnect…") {
                    appState.ui.connectAccountRequest = ConnectAccountRequest(instanceId: instanceId, replacing: row.id)
                }
                Button("Test connection") { test(row) }
                Menu("Link to profile") {
                    Button { store.linkAccount(row.id, toProfile: nil) } label: {
                        checked("None", row.linkedProfileId == nil)
                    }
                    ForEach(appState.profiles.profiles) { profile in
                        Button { store.linkAccount(row.id, toProfile: profile.id) } label: {
                            checked(profile.name, row.linkedProfileId == profile.id)
                        }
                    }
                }
                Divider()
                Button("Disconnect…", role: .destructive) { disconnecting = row }
            } label: { Image(systemName: "ellipsis") }
            .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.plain).fixedSize()
            .help("Account options")
        }
        .padding(.horizontal, Spacing.s12).padding(.vertical, Spacing.s8)
        .overlay(alignment: .top) { Rectangle().fill(theme.colors.separator).frame(height: 1) }
    }

    @ViewBuilder
    private func checked(_ title: String, _ isOn: Bool) -> some View {
        if isOn { Label(title, systemImage: "checkmark") } else { Text(title) }
    }

    private func statusPill(_ row: AccountRowModel) -> some View {
        let (fg, bg): (Color, Color) = switch row.tone {
        case .ok: (theme.colors.ok, theme.colors.okSoft)
        case .warn: (theme.colors.warn, theme.colors.warnSoft)
        case .bad: (theme.colors.del, theme.colors.delSoft)
        }
        return Text(row.statusText)
            .textRole(.caption, weight: .semibold)
            .foregroundStyle(fg)
            .lineLimit(1)
            .padding(.horizontal, Spacing.s6).padding(.vertical, 2)
            .background(Capsule().fill(bg))
    }

    private func tag(_ text: String) -> some View {
        Text(text).textRole(.caption).foregroundStyle(theme.colors.textSecondary)
            .padding(.horizontal, Spacing.s6).padding(.vertical, 1)
            .background(Capsule().fill(theme.colors.fillControl))
    }

    private func test(_ row: AccountRowModel) {
        guard let account = store.accounts.first(where: { $0.id == row.id }) else { return }
        Task {
            await appState.accountValidator.validate(account)
            guard let after = store.accounts.first(where: { $0.id == row.id }) else { return }
            let kind = store.instances.first { $0.id == after.instanceId }?.kind ?? .github
            let ok = after.status == .ok || after.status == .expiringSoon
            let status = AccountsSettingsModel.status(after, kind: kind, now: .now).0
            appState.ui.activeToast = ToastMessage(message: ok ? "\(after.login ?? "Account") is connected"
                                                         : "\(after.login ?? row.title): \(status)",
                                                   kind: ok ? .ok : .warn)
        }
    }

    private func clientIdSheet(_ instance: HostingInstance) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            Text("OAuth client ID for \(instance.host)").textRole(.headline)
            Text("Register an application on that instance (non-confidential, scopes api, read_user, write_repository) and paste its Application ID.")
                .textRole(.callout).foregroundStyle(theme.colors.textSecondary)
            GFTextField(placeholder: "Application ID", text: $clientIdDraft)
            HStack {
                Spacer()
                GFButton(title: "Cancel") { clientIdInstance = nil }
                GFButton(title: "Save", style: .primary) {
                    store.setOAuthClientId(clientIdDraft, forInstance: instance.id)
                    clientIdInstance = nil
                }
            }
        }
        .padding(Spacing.s16)
        .frame(width: 420)
    }
}

/// Avatar from the account's URL, or its initials.
private struct AccountAvatar: View {
    let initials: String
    let url: URL?
    @State private var image: NSImage?
    @Environment(\.appTheme) private var theme

    var body: some View {
        ZStack {
            Circle().fill(theme.colors.fillControl)
            if let image {
                Image(nsImage: image).resizable().scaledToFill().clipShape(Circle())
            } else {
                Text(initials).textRole(.caption, weight: .bold).foregroundStyle(theme.colors.textSecondary)
            }
        }
        .frame(width: 26, height: 26)
        .task(id: url) {
            guard let url else { return }
            image = await AvatarLoader.shared.image(for: url)
        }
        .accessibilityHidden(true)
    }
}
