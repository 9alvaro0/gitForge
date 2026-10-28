import SwiftUI

/// The main column of the Settings mode: the pane the sidebar has selected.
/// Every section owns its own state and persistence, so this file only picks
/// which ones to stack, and pads and centres them.
struct SettingsView: View {
    @Environment(\.appTheme) private var theme
    @Environment(GitEnvironment.self) private var gitEnvironment
    @Environment(AppState.self) private var appState

    /// Widest the stack of sections grows; a wider window leaves margins.
    private static let maxContentWidth: CGFloat = 680

    var body: some View {
        let pane = appState.ui.settingsPane
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s24) {
                content(of: pane)
            }
            .frame(maxWidth: Self.maxContentWidth, alignment: .topLeading)
            .padding(Spacing.s24)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        // Each pane scrolls on its own: switching starts at the top rather
        // than at the offset of the pane before.
        .id(pane)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.colors.bgContent)
        .navigationTitle("Settings")
        .task { await gitEnvironment.refreshGlobalConfig() }
    }

    @ViewBuilder
    private func content(of pane: SettingsPane) -> some View {
        switch pane {
        case .general:
            LanguageSection()
            UpdatesSection()
        case .appearance:
            AppearanceSection()
        case .identities:
            IdentitySection()
            ProfilesSection()
        case .accounts:
            AccountsSection()
        case .git:
            GitSection()
            BehaviorSection()
        case .pullRequests:
            ReviewsSettingsSection(store: appState.reviews)
        }
    }
}

// MARK: - Previews

/// Opens `SettingsView` on a pane, in its own theme.
private struct SettingsViewPreview: View {
    let pane: SettingsPane

    @State private var theme = AppTheme()
    @State private var state = AppState.preview

    var body: some View {
        SettingsView()
            .previewAppState(state)
            .frame(width: 980, height: 620)
            .appTheme(theme)
            .onAppear { state.ui.settingsPane = pane }
    }
}

#Preview("General") { SettingsViewPreview(pane: .general) }
#Preview("Appearance") { SettingsViewPreview(pane: .appearance) }
#Preview("Identities") { SettingsViewPreview(pane: .identities) }
#Preview("Accounts") { SettingsViewPreview(pane: .accounts) }
#Preview("Git") { SettingsViewPreview(pane: .git) }
#Preview("Pull requests") { SettingsViewPreview(pane: .pullRequests) }
