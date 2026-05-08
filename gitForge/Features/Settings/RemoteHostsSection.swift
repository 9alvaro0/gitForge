import SwiftUI

/// Settings section managing Personal Access Tokens for remote hosting
/// platforms. Tokens are stored in the Keychain via `RemoteCredentialsStore`.
struct RemoteHostsSection: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppState.self) private var appState

    @State private var configured: [String: Bool] = [:]
    @State private var trusted: Set<String> = []
    @State private var editing: HostEntry?
    @State private var draftToken: String = ""
    @State private var sheetError: String?

    private static let defaults: [HostEntry] = [
        HostEntry(provider: .github, host: "github.com",
                  scopeHint: "Required scope: `repo` (for private repos) or `public_repo`."),
        HostEntry(provider: .gitlab, host: "gitlab.com",
                  scopeHint: "Required scope: `read_api` (or `api` to create MRs later)."),
    ]

    /// The defaults plus any host detected from the active repo (so self-hosted
    /// GitLab / GitHub Enterprise instances appear here automatically).
    private var entries: [HostEntry] {
        var result = Self.defaults
        if let host = appState.catalog.activeViewModel?.pullRequestsHost,
           !result.contains(where: { $0.host == host.host }) {
            result.append(HostEntry(
                provider: host.provider,
                host: host.host,
                scopeHint: host.provider == .github
                    ? "Required scope: `repo` (private) or `public_repo`."
                    : "Required scope: `read_api` (or `api` for write actions)."
            ))
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            Text("Remote hosts".uppercased())
                .font(.system(size: FontSize.footnote, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(theme.palette.fg3)
            VStack(spacing: DesignTokens.Spacing.xs) {
                ForEach(entries) { entry in
                    hostRow(entry)
                }
            }
        }
        .onAppear { refreshConfiguredState() }
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
                    RemoteHostTrust.shared.setTrusted(entry.host, !isTrusted)
                    refreshConfiguredState()
                } label: {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Text(isTrusted ? "☑" : "☐")
                            .font(AppFont.sans(13))
                            .foregroundStyle(isTrusted ? theme.palette.mod : theme.palette.fg3)
                        Text("Trust self-signed certificate")
                            .font(AppFont.sans(11))
                            .foregroundStyle(theme.palette.fg2)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                if isTrusted {
                    Text("• Skips TLS validation for this host")
                        .font(AppFont.sans(11))
                        .foregroundStyle(theme.palette.fg3)
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.lg)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
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
        .padding(DesignTokens.Spacing.huge)
        .frame(width: 600)
        .background(theme.palette.bg2)
        .appTheme(theme)
}
