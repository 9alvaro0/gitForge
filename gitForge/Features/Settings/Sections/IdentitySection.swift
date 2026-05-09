import SwiftUI

struct IdentitySection: View {
    @Environment(GitEnvironment.self) private var gitEnvironment
    @Environment(WorkspaceUI.self) private var ui

    var body: some View {
        SettingsSection(title: "Identity") {
            SettingsEditableRow(label: "Name",
                                value: gitEnvironment.globalConfig.identity.name) { value in
                guard let value else { return }
                apply("Couldn’t update name") {
                    try await gitEnvironment.setIdentity(name: value)
                }
            }
            SettingsDivider()
            SettingsEditableRow(label: "Email",
                                value: gitEnvironment.globalConfig.identity.email,
                                mono: true) { value in
                guard let value else { return }
                apply("Couldn’t update email") {
                    try await gitEnvironment.setIdentity(email: value)
                }
            }
            SettingsDivider()
            SettingsEditableRow(label: "Signing key",
                                value: gitEnvironment.globalConfig.signingKey,
                                mono: true,
                                placeholder: "GPG / SSH key id (optional)") { value in
                apply("Couldn’t update signing key") {
                    try await gitEnvironment.setSigningKey(value)
                }
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
    IdentitySection()
        .previewAppState(.preview)
        .frame(width: 560)
        .padding(DesignTokens.Spacing.huge)
        .background(theme.palette.bg2)
        .appTheme(theme)
}
