import SwiftUI

/// "Git is required" block with the Command Line Tools installer and a
/// recheck button. Shared by the onboarding step (`GitStep`) and the
/// post-onboarding gate (`GitNotFoundView`), which used to carry two copies.
struct GitInstallPrompt: View {
    @Environment(GitEnvironment.self) private var gitEnvironment
    @Environment(\.appTheme) private var theme
    @State private var isInstalling = false

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xxl) {
            StatusBadge(icon: .warn, tint: theme.palette.warn)
            VStack(spacing: DesignTokens.Spacing.sm) {
                Text("Git is required")
                    .font(AppFont.sans(FontSize.xxxl, weight: .semibold))
                    .foregroundStyle(theme.palette.fg1)
                Text("gitForge needs the `git` command-line tool. Install the Xcode Command Line Tools to continue.")
                    .font(AppFont.sans(FontSize.md))
                    .foregroundStyle(theme.palette.fg3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            HStack(spacing: DesignTokens.Spacing.md) {
                GFButton(
                    title: isInstalling ? "Installing…" : "Install Command Line Tools",
                    style: .primary,
                    disabled: isInstalling
                ) {
                    isInstalling = true
                    Task {
                        await gitEnvironment.installCommandLineTools()
                        isInstalling = false
                    }
                }
                GFButton(title: "Recheck") {
                    Task { await gitEnvironment.refreshGitInstallation() }
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    GitInstallPrompt()
        .previewAppState(.previewMissingGit)
        .padding(DesignTokens.Spacing.xxxhuge)
        .frame(width: 720, height: 420)
        .background(theme.palette.bg2)
        .appTheme(theme)
}
