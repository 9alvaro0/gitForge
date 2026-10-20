import SwiftUI

/// Auto-fetch needs to bounce the active VM's reactivity timer once the
/// new interval persists — otherwise runtime polling keeps the old period
/// and drifts from what's saved on disk.
struct GitSection: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppState.self) private var appState
    @Environment(GitEnvironment.self) private var gitEnvironment
    @Environment(WorkspaceUI.self) private var ui

    var body: some View {
        SettingsSection(title: "Git") {
            SettingsEditableRow(label: String(localized: "Default branch"),
                                value: gitEnvironment.globalConfig.defaultBranch,
                                mono: true,
                                placeholder: "main") { value in
                apply(String(localized: "Couldn’t update default branch")) {
                    try await gitEnvironment.setDefaultBranch(value)
                }
            }
            SettingsDivider()
            pullStrategyRow
            SettingsDivider()
            autoFetchRow
        }
    }

    private var pullStrategyRow: some View {
        HStack {
            SettingsRowLabel(text: String(localized: "Pull strategy"))
            Spacer(minLength: 0)
            SettingsPicker(current: gitEnvironment.globalConfig.pullStrategy
                            ?? String(localized: "settings.pullStrategy.default", defaultValue: "default")) {
                Button("Default (git config)") { setPullStrategy(nil) }
                Divider()
                Button("Rebase") { setPullStrategy("rebase") }
                Button("Merge") { setPullStrategy("merge") }
                Button("Fast-forward only") { setPullStrategy("ff-only") }
            }
            .frame(maxWidth: 240)
        }
        .padding(.horizontal, Spacing.s12)
        .padding(.vertical, Spacing.s8)
    }

    private var autoFetchRow: some View {
        HStack {
            SettingsRowLabel(text: String(localized: "Auto-fetch"))
            Spacer(minLength: 0)
            SettingsPicker(current: autoFetchLabel) {
                Button("Off") { setAutoFetch(nil) }
                Divider()
                Button("Every 1 min")  { setAutoFetch(60) }
                Button("Every 5 min")  { setAutoFetch(300) }
                Button("Every 10 min") { setAutoFetch(600) }
                Button("Every 15 min") { setAutoFetch(900) }
                Button("Every 30 min") { setAutoFetch(1800) }
            }
            .frame(maxWidth: 240)
        }
        .padding(.horizontal, Spacing.s12)
        .padding(.vertical, Spacing.s8)
    }

    private var autoFetchLabel: String {
        guard let interval = gitEnvironment.globalConfig.autoFetchInterval, interval > 0 else { return String(localized: "Off") }
        if interval >= 60 { return String(localized: "Every \(interval / 60) min") }
        return String(localized: "Every \(interval) sec")
    }

    private func setPullStrategy(_ value: String?) {
        apply(String(localized: "Couldn’t update pull strategy")) {
            try await gitEnvironment.setPullStrategy(value)
        }
    }

    private func setAutoFetch(_ seconds: Int?) {
        Task {
            do {
                try await gitEnvironment.setAutoFetchInterval(seconds)
                appState.catalog.activeViewModel?.startReactivity(
                    autoFetchIntervalSeconds: gitEnvironment.globalConfig.autoFetchInterval ?? 0
                )
            } catch {
                ui.presentedError = PresentedError(error: error, title: String(localized: "Couldn’t update auto-fetch"))
            }
        }
    }

    private func apply(_ title: String, _ work: @escaping () async throws -> Void) {
        Task {
            do { try await work() }
            catch { ui.presentedError = PresentedError(error: error, title: title) }
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    GitSection()
        .previewAppState(.preview)
        .frame(width: 560)
        .padding(Spacing.s20)
        .background(theme.colors.bgContent)
        .appTheme(theme)
}
