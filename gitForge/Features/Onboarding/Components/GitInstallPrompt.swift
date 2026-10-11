import SwiftUI

/// "Git is required" block with the Command Line Tools installer and a
/// recheck button. Shared by the onboarding step (`GitStep`) and the
/// post-onboarding gate (`GitNotFoundView`), which used to carry two copies.
struct GitInstallPrompt: View {
    @Environment(GitEnvironment.self) private var gitEnvironment
    @Environment(\.appTheme) private var theme
    @State private var isInstalling = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            HStack(alignment: .top, spacing: Spacing.s12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(theme.colors.warn)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: Radius.control).fill(theme.colors.warnSoft))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    Text("Git is required")
                        .textRole(.body, weight: .semibold)
                        .foregroundStyle(theme.colors.textPrimary)
                    Text("gitForge needs the `git` command-line tool. Install the Xcode Command Line Tools to continue.")
                        .textRole(.callout)
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
            HStack(spacing: Spacing.s8) {
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
        .padding(Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card).fill(theme.colors.bgElevated))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(theme.colors.separator, lineWidth: 1))
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    GitInstallPrompt()
        .previewAppState(.previewMissingGit)
        .padding(Spacing.s48)
        .frame(width: 720, height: 420)
        .background(theme.colors.bgContent)
        .appTheme(theme)
}
