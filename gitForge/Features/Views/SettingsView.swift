import SwiftUI

/// `.gf-view-settings` — identity, git, accounts. Reads global git config
/// from `AppState.globalConfig`; the inline name/email editor writes back via
/// `AppState.updateIdentity`.
struct SettingsView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppState.self) private var appState

    @State private var editing: EditingField?
    @State private var draftValue: String = ""

    enum EditingField: String, Identifiable { case name, email; var id: String { rawValue } }

    var body: some View {
        VStack(spacing: 0) {
            ContentHeader(title: "Settings")
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible(), spacing: 24)],
                          alignment: .leading, spacing: 24) {
                    identitySection
                    gitSection
                }
                .padding(18)
                .frame(maxWidth: 900, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.bg2)
        .task { await appState.refreshGlobalConfig() }
    }

    private var identitySection: some View {
        section(title: "Identity") {
            editableRow(label: "Name", value: appState.globalConfig.identity.name, field: .name, mono: false)
            editableRow(label: "Email", value: appState.globalConfig.identity.email, field: .email, mono: true)
            settingRow(label: "Signing key", value: appState.globalConfig.signingKey ?? "—", mono: true)
        }
    }

    private var gitSection: some View {
        section(title: "Git") {
            settingRow(label: "Default branch", value: appState.globalConfig.defaultBranch ?? "—", mono: true)
            settingRow(label: "Pull strategy", value: appState.globalConfig.pullStrategy ?? "—", mono: true)
            settingRow(label: "Auto-fetch", value: autoFetchLabel, mono: false)
        }
    }

    private var autoFetchLabel: String {
        guard let interval = appState.globalConfig.autoFetchInterval else { return "off" }
        if interval >= 60 { return "every \(interval / 60) min" }
        return "every \(interval) sec"
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
            rowLabel(label)
            Text(value)
                .font(mono ? AppFont.mono(12, family: theme.monoFont) : AppFont.sans(12))
                .foregroundStyle(theme.palette.fg1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .modifier(SettingRowChrome(theme: theme))
    }

    @ViewBuilder
    private func editableRow(label: String, value: String?, field: EditingField, mono: Bool) -> some View {
        HStack {
            rowLabel(label)
            if editing == field {
                TextField("", text: $draftValue)
                    .textFieldStyle(.plain)
                    .font(mono ? AppFont.mono(12, family: theme.monoFont) : AppFont.sans(12))
                    .foregroundStyle(theme.palette.fg1)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 4).fill(theme.palette.bg2))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.palette.accent, lineWidth: 1))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onSubmit { commit(field: field) }
                GFButton(title: "Save", style: .primary, size: .small) { commit(field: field) }
                GFButton(title: "Cancel", size: .small) { editing = nil }
            } else {
                Text(value ?? "—")
                    .font(mono ? AppFont.mono(12, family: theme.monoFont) : AppFont.sans(12))
                    .foregroundStyle(value == nil ? theme.palette.fg3 : theme.palette.fg1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                GFButton(title: "Edit", size: .small) {
                    draftValue = value ?? ""
                    editing = field
                }
            }
        }
        .modifier(SettingRowChrome(theme: theme))
    }

    @ViewBuilder
    private func rowLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .medium))
            .tracking(0.6)
            .foregroundStyle(theme.palette.fg3)
            .frame(width: 130, alignment: .leading)
    }

    private func commit(field: EditingField) {
        let value = draftValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { editing = nil; return }
        Task {
            switch field {
            case .name:  await appState.updateIdentity(name: value)
            case .email: await appState.updateIdentity(email: value)
            }
            editing = nil
        }
    }
}

private struct SettingRowChrome: ViewModifier {
    let theme: AppTheme
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: 1))
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    SettingsView()
        .environment(AppState.preview)
        .frame(width: 980, height: 620)
        .appTheme(theme)
}
