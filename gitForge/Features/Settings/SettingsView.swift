import SwiftUI

/// `.gf-view-settings` — appearance, identity, git config, all editable from
/// the UI. No CLI homework required.
struct SettingsView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppState.self) private var appState

    @State private var editing: EditingField?
    @State private var draftValue: String = ""

    enum EditingField: String, Identifiable {
        case name, email, signingKey, defaultBranch
        var id: String { rawValue }
    }

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
                    RemoteHostsSection()
                }
                .padding(18)
                .frame(maxWidth: 900, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.bg2)
        .task { await appState.refreshGlobalConfig() }
    }

    // MARK: Appearance

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
            radioRow(label: "Diff view",
                     values: DiffPane.ViewMode.allCases.map { ($0.rawValue, $0.label) },
                     current: appState.theme.defaultDiffMode.rawValue) { v in
                if let m = DiffPane.ViewMode(rawValue: v) { appState.theme.defaultDiffMode = m }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Identity

    private var identitySection: some View {
        section(title: "Identity") {
            editableRow(label: "Name", value: appState.globalConfig.identity.name, field: .name, mono: false)
            editableRow(label: "Email", value: appState.globalConfig.identity.email, field: .email, mono: true)
            editableRow(label: "Signing key", value: appState.globalConfig.signingKey, field: .signingKey, mono: true,
                        placeholder: "GPG / SSH key id (optional)")
        }
    }

    // MARK: Git

    private var gitSection: some View {
        section(title: "Git") {
            editableRow(label: "Default branch", value: appState.globalConfig.defaultBranch, field: .defaultBranch, mono: true,
                        placeholder: "main")
            pullStrategyRow
            autoFetchRow
        }
    }

    private var pullStrategyRow: some View {
        HStack {
            rowLabel("Pull strategy")
            let current = appState.globalConfig.pullStrategy ?? "default"
            Menu {
                Button("Default (git config)") { Task { await appState.updatePullStrategy(nil) } }
                Divider()
                Button("Rebase")            { Task { await appState.updatePullStrategy("rebase") } }
                Button("Merge")             { Task { await appState.updatePullStrategy("merge") } }
                Button("Fast-forward only") { Task { await appState.updatePullStrategy("ff-only") } }
            } label: {
                pickerLabel(current)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .frame(maxWidth: 240, alignment: .trailing)
        }
        .modifier(SettingRowChrome(theme: theme))
    }

    private var autoFetchRow: some View {
        HStack {
            rowLabel("Auto-fetch")
            let current = autoFetchLabel
            Menu {
                Button("Off") { Task { await appState.updateAutoFetchInterval(nil) } }
                Divider()
                Button("Every 1 min")  { Task { await appState.updateAutoFetchInterval(60) } }
                Button("Every 5 min")  { Task { await appState.updateAutoFetchInterval(300) } }
                Button("Every 10 min") { Task { await appState.updateAutoFetchInterval(600) } }
                Button("Every 15 min") { Task { await appState.updateAutoFetchInterval(900) } }
                Button("Every 30 min") { Task { await appState.updateAutoFetchInterval(1800) } }
            } label: {
                pickerLabel(current)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .frame(maxWidth: 240, alignment: .trailing)
        }
        .modifier(SettingRowChrome(theme: theme))
    }

    private var autoFetchLabel: String {
        guard let interval = appState.globalConfig.autoFetchInterval, interval > 0 else { return "Off" }
        if interval >= 60 { return "Every \(interval / 60) min" }
        return "Every \(interval) sec"
    }

    @ViewBuilder
    private func pickerLabel(_ text: String) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(AppFont.sans(12))
                .foregroundStyle(theme.palette.fg1)
            Spacer(minLength: 0)
            GFIcon(kind: .chevD, size: 10, stroke: theme.palette.fg3)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 4).fill(theme.palette.bg2))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.palette.lineStrong, lineWidth: 1))
    }

    // MARK: Generic rows / editing

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
    private func editableRow(label: String,
                              value: String?,
                              field: EditingField,
                              mono: Bool,
                              placeholder: String = "") -> some View {
        HStack {
            rowLabel(label)
            if editing == field {
                TextField(placeholder, text: $draftValue)
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
        let trimmed = draftValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: String? = trimmed.isEmpty ? nil : trimmed
        Task {
            switch field {
            case .name:
                if let value { await appState.updateIdentity(name: value) }
            case .email:
                if let value { await appState.updateIdentity(email: value) }
            case .signingKey:
                await appState.updateSigningKey(value)
            case .defaultBranch:
                await appState.updateDefaultBranch(value)
            }
            editing = nil
        }
    }

    // MARK: Appearance pickers

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
