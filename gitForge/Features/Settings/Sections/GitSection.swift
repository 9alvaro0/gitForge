import SwiftUI

/// Default branch + pull strategy + auto-fetch interval. Auto-fetch needs
/// to bounce the active VM's reactivity timer once the value persists,
/// otherwise runtime polling drifts from what's saved.
struct GitSection: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppState.self) private var appState
    @Environment(GitEnvironment.self) private var gitEnvironment
    @Environment(WorkspaceUI.self) private var ui

    var body: some View {
        SettingsSection(title: "Git") {
            SettingsEditableRow(label: "Default branch",
                                value: gitEnvironment.globalConfig.defaultBranch,
                                mono: true,
                                placeholder: "main") { value in
                apply("Couldn’t update default branch") {
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
            SettingsRowLabel(text: "Pull strategy")
            Spacer(minLength: 0)
            SettingsPicker(current: gitEnvironment.globalConfig.pullStrategy ?? "default") {
                Button("Default (git config)") { setPullStrategy(nil) }
                Divider()
                Button("Rebase") { setPullStrategy("rebase") }
                Button("Merge") { setPullStrategy("merge") }
                Button("Fast-forward only") { setPullStrategy("ff-only") }
            }
            .frame(maxWidth: 240)
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    private var autoFetchRow: some View {
        HStack {
            SettingsRowLabel(text: "Auto-fetch")
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
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    private var autoFetchLabel: String {
        guard let interval = gitEnvironment.globalConfig.autoFetchInterval, interval > 0 else { return "Off" }
        if interval >= 60 { return "Every \(interval / 60) min" }
        return "Every \(interval) sec"
    }

    private func setPullStrategy(_ value: String?) {
        apply("Couldn’t update pull strategy") {
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
                ui.presentedError = PresentedError(error: error, title: "Couldn’t update auto-fetch")
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
        .padding(DesignTokens.Spacing.huge)
        .background(theme.palette.bg2)
        .appTheme(theme)
}
