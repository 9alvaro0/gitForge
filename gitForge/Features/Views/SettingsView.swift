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
                VStack(alignment: .leading, spacing: 24) {
                    appearanceSection
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible(), spacing: 24)],
                              alignment: .leading, spacing: 24) {
                        identitySection
                        gitSection
                    }
                }
                .padding(18)
                .frame(maxWidth: 900, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.bg2)
        .task { await appState.refreshGlobalConfig() }
    }

    private var appearanceSection: some View {
        section(title: "Appearance") {
            HStack(alignment: .top, spacing: 24) {
                appearanceColumn
                codeColumn
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: 1))
        }
    }

    private var appearanceColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            radioRow(label: "Theme",
                     values: ThemeMode.allCases.map { ($0.rawValue, $0.label) },
                     current: appState.theme.mode.rawValue) { v in
                if let m = ThemeMode(rawValue: v) { appState.theme.mode = m }
            }
            colorRow(label: "Accent",
                     swatches: AppTheme.accentSwatches,
                     current: appState.theme.accent) { appState.theme.accent = $0 }
            radioRow(label: "Density",
                     values: Density.allCases.map { ($0.rawValue, $0.label) },
                     current: appState.theme.density.rawValue) { v in
                if let d = Density(rawValue: v) { appState.theme.density = d }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var codeColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            selectRow(label: "Mono font",
                      values: MonoFontFamily.allCases.map { ($0.rawValue, $0.label) },
                      current: appState.theme.monoFont.rawValue) { v in
                if let f = MonoFontFamily(rawValue: v) { appState.theme.monoFont = f }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func radioRow(label: String, values: [(String, String)], current: String, onChange: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(AppFont.sans(11, weight: .medium)).foregroundStyle(theme.palette.fg3)
            HStack(spacing: 4) {
                ForEach(values, id: \.0) { (raw, label) in
                    Button(action: { onChange(raw) }) {
                        Text(label.capitalized)
                            .font(AppFont.sans(11))
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .foregroundStyle(raw == current ? theme.palette.accent : theme.palette.fg2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(raw == current ? theme.palette.accentSoft : theme.palette.bg2))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func colorRow(label: String, swatches: [Color], current: Color, onChange: @escaping (Color) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(AppFont.sans(11, weight: .medium)).foregroundStyle(theme.palette.fg3)
            HStack(spacing: 8) {
                ForEach(Array(swatches.enumerated()), id: \.offset) { _, c in
                    Button(action: { onChange(c) }) {
                        Circle()
                            .fill(c)
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(c == current ? theme.palette.fg1 : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func selectRow(label: String, values: [(String, String)], current: String, onChange: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(AppFont.sans(11, weight: .medium)).foregroundStyle(theme.palette.fg3)
            Menu {
                ForEach(values, id: \.0) { (raw, label) in
                    Button(label) { onChange(raw) }
                }
            } label: {
                HStack {
                    Text(current).font(AppFont.sans(12))
                    Spacer()
                    GFIcon(kind: .chevD, size: 10, stroke: theme.palette.fg3)
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .foregroundStyle(theme.palette.fg1)
                .background(RoundedRectangle(cornerRadius: 6).fill(theme.palette.bg2))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.palette.lineStrong, lineWidth: 1))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .frame(maxWidth: 240)
        }
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
