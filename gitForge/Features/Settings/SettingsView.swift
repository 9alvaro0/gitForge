import SwiftUI

/// `.gf-view-settings` — appearance, identity, git config, remote hosts.
/// Pure compositor: stacks the four sections vertically inside a scroll
/// view. Each section owns its own state and persistence calls.
struct SettingsView: View {
    @Environment(\.appTheme) private var theme
    @Environment(GitEnvironment.self) private var gitEnvironment

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.none) {
            ContentHeader(title: "Settings")
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xhuge) {
                    AppearanceSection()
                    IdentitySection()
                    GitSection()
                    RemoteHostsSection()
                }
                .padding(DesignTokens.Spacing.xxxxl)
                .frame(maxWidth: 760, alignment: .topLeading)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.bg2)
        .task { await gitEnvironment.refreshGlobalConfig() }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    SettingsView()
        .previewAppState(.preview)
        .frame(width: 980, height: 620)
        .appTheme(theme)
}
