import SwiftUI

/// `.gf-view-settings` — identity, git, accounts.
struct SettingsView: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ContentHeader(title: "Settings")
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible(), spacing: 24)],
                          alignment: .leading, spacing: 24) {
                    section(title: "Identity") {
                        settingRow(label: "Name", value: "Mateo Vélez", mono: false)
                        settingRow(label: "Email", value: "m@velez.dev", mono: true)
                        settingRow(label: "Signing key", value: "ed25519 · 4096", mono: true)
                    }
                    section(title: "Git") {
                        settingRow(label: "Default branch", value: "main", mono: true)
                        settingRow(label: "Pull strategy", value: "rebase", mono: true)
                        settingRow(label: "Auto-fetch", value: "every 5 min", mono: false)
                    }
                    section(title: "Accounts") {
                        accountRow(host: "github.com", user: "mvelez")
                        accountRow(host: "gitlab.com", user: "m.velez")
                        accountRow(host: "gitea.acme.io", user: "mvelez")
                    }
                }
                .padding(18)
                .frame(maxWidth: 900, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.bg2)
    }

    @ViewBuilder
    private func section<C: View>(title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(theme.palette.fg3)
            VStack(spacing: 4) { content() }
        }
    }

    @ViewBuilder
    private func settingRow(label: String, value: String, mono: Bool) -> some View {
        HStack {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(theme.palette.fg3)
                .frame(width: 130, alignment: .leading)
            Text(value)
                .font(mono ? AppFont.mono(12, family: theme.monoFont) : AppFont.sans(12))
                .foregroundStyle(theme.palette.fg1)
                .frame(maxWidth: .infinity, alignment: .leading)
            GFButton(title: "Edit", size: .small) { }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: 1))
    }

    @ViewBuilder
    private func accountRow(host: String, user: String) -> some View {
        HStack {
            Text(host)
                .font(AppFont.mono(12, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg1)
                .frame(width: 130, alignment: .leading)
            Text("@\(user)")
                .font(AppFont.mono(12, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
                .frame(maxWidth: .infinity, alignment: .leading)
            GFButton(title: "Sign out", size: .small) { }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: 1))
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    SettingsView()
        .frame(width: 980, height: 620)
        .appTheme(theme)
}
