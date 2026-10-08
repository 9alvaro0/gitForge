import SwiftUI

/// Tokens land in the Keychain via `RemoteCredentialsStore`; per-host pinned
/// certificates live in `RemoteHostTrust`. The default list (github.com /
/// gitlab.com) gets the active repo's host appended at render time so
/// self-hosted instances show up without per-user configuration.
struct RemoteHostsSection: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppState.self) private var appState

    @State private var configured: [String: Bool] = [:]
    @State private var trusted: Set<String> = []
    @State private var editing: HostEntry?
    @State private var draftToken: String = ""
    @State private var sheetError: String?
    @State private var trustHost: String?

    /// gitForge only reads from GitHub, so a read-only fine-grained token is
    /// enough; the classic `repo` scope also grants write access.
    private static let gitHubScopeHint =
        "Recommended: a fine-grained token with read-only access to Pull requests, Contents and Commit statuses. Classic tokens need `repo` (private) or `public_repo`."

    private static let defaults: [HostEntry] = [
        HostEntry(provider: .github, host: "github.com",
                  scopeHint: Self.gitHubScopeHint),
        HostEntry(provider: .gitlab, host: "gitlab.com",
                  scopeHint: "Required scope: `read_api` (or `api` to create MRs later)."),
    ]

    private var entries: [HostEntry] {
        var result = Self.defaults
        if let host = appState.catalog.activeViewModel?.pullRequests.host,
           !result.contains(where: { $0.host == host.host }) {
            result.append(HostEntry(
                provider: host.provider,
                host: host.host,
                scopeHint: host.provider == .github
                    ? Self.gitHubScopeHint
                    : "Required scope: `read_api` (or `api` for write actions)."
            ))
        }
        return result
    }

    var body: some View {
        SettingsSection(title: "Remote hosts") {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { SettingsDivider() }
                hostRow(entry)
            }
        }
        .onAppear { refreshConfiguredState() }
        .trustCertificatePrompt(host: $trustHost) { refreshConfiguredState() }
        .sheet(item: $editing) { entry in
            tokenSheet(for: entry)
        }
    }

    @ViewBuilder
    private func hostRow(_ entry: HostEntry) -> some View {
        let hasToken = configured[entry.host] ?? false
        let isTrusted = trusted.contains(entry.host)
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Text(entry.provider.label)
                            .font(AppFont.sans(12, weight: .medium))
                            .foregroundStyle(theme.palette.fg1)
                        MonoText(entry.host, dim: true)
                    }
                    Text(hasToken ? "Token configured" : "No token")
                        .font(AppFont.sans(11))
                        .foregroundStyle(hasToken ? theme.palette.ok : theme.palette.fg3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: DesignTokens.Spacing.sm) {
                    GFButton(title: hasToken ? "Replace…" : "Set token…", size: .small) {
                        draftToken = ""
                        editing = entry
                    }
                    if hasToken {
                        GFButton(title: "Remove", size: .small) {
                            RemoteCredentialsStore.shared.removeToken(for: entry.host)
                            refreshConfiguredState()
                        }
                    }
                }
            }
            HStack(spacing: DesignTokens.Spacing.sm) {
                Button {
                    if isTrusted {
                        RemoteHostTrust.shared.revoke(entry.host)
                        refreshConfiguredState()
                    } else {
                        // Reads the certificate and asks for confirmation.
                        trustHost = entry.host
                    }
                } label: {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Text(isTrusted ? "☑" : "☐")
                            .font(AppFont.sans(13))
                            .foregroundStyle(isTrusted ? theme.palette.mod : theme.palette.fg3)
                        Text("Trust this host's certificate")
                            .font(AppFont.sans(11))
                            .foregroundStyle(theme.palette.fg2)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                if isTrusted {
                    Text(pinDescription(for: entry.host))
                        .font(AppFont.mono(10.5, family: theme.monoFont))
                        .foregroundStyle(theme.palette.fg3)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(RemoteHostTrust.shared.pinnedFingerprint(for: entry.host) ?? "")
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.lg)
    }

    @ViewBuilder
    private func tokenSheet(for entry: HostEntry) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            Text("\(entry.provider.label) token")
                .font(AppFont.sans(14, weight: .semibold))
            Text(entry.scopeHint)
                .font(AppFont.sans(11))
                .foregroundStyle(theme.palette.fg3)
                .fixedSize(horizontal: false, vertical: true)
            SecureField("ghp_… / glpat_…", text: $draftToken)
                .textFieldStyle(.plain)
                .font(AppFont.mono(12, family: theme.monoFont))
                .padding(.horizontal, DesignTokens.Spacing.md)
                .frame(height: DesignTokens.Control.height)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).fill(theme.palette.bg2))
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).stroke(theme.palette.lineStrong, lineWidth: DesignTokens.Stroke.regular))
            if let sheetError {
                Text(sheetError)
                    .font(AppFont.sans(11))
                    .foregroundStyle(theme.palette.del)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                GFButton(title: "Cancel") {
                    sheetError = nil
                    editing = nil
                }
                Spacer()
                GFButton(title: "Save", style: .primary) {
                    let value = draftToken.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let error = RemoteCredentialsStore.shared.setToken(value, for: entry.host) {
                        sheetError = error
                    } else {
                        sheetError = nil
                        refreshConfiguredState()
                        editing = nil
                    }
                }
                .disabled(draftToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(DesignTokens.Spacing.huge)
        .frame(width: 460)
        .background(theme.palette.bg1)
        .appTheme(theme)
    }

    /// Hosts trusted before pinning existed pin on their next connection.
    private func pinDescription(for host: String) -> String {
        guard let fingerprint = RemoteHostTrust.shared.pinnedFingerprint(for: host) else {
            return "• Certificate will be pinned on next connection"
        }
        return "• Pinned SHA-256 \(fingerprint.prefix(23))…"
    }

    private func refreshConfiguredState() {
        var snapshot: [String: Bool] = [:]
        for entry in entries {
            snapshot[entry.host] = RemoteCredentialsStore.shared.hasToken(for: entry.host)
        }
        configured = snapshot
        trusted = Set(RemoteHostTrust.shared.trustedHosts())
    }
}

private struct HostEntry: Identifiable, Equatable {
    let provider: RemoteProvider
    let host: String
    let scopeHint: String
    var id: String { host }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    RemoteHostsSection()
        .previewAppState(.preview)
        .frame(width: 600)
        .padding(DesignTokens.Spacing.huge)
        .background(theme.palette.bg2)
        .appTheme(theme)
}
