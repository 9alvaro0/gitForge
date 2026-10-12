import SwiftUI

/// Pure compositor for the Settings page — every section owns its own
/// state and persistence so this file never grows past stacking + padding.
struct SettingsView: View {
    @Environment(\.appTheme) private var theme
    @Environment(GitEnvironment.self) private var gitEnvironment

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s24) {
                    AppearanceSection()
                    IdentitySection()
                    ProfilesSection()
                    GitSection()
                    BehaviorSection()
                    AccountsSection()
                }
                .padding(Spacing.s20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.colors.bgContent)
        .navigationTitle("Settings")
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
