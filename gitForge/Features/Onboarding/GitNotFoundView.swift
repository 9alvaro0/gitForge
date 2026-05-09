import SwiftUI

/// Post-onboarding gate: shown when `gitEnvironment.gitStatus == .notFound`
/// after the user has already finished the initial flow (e.g. they
/// uninstalled git later). Mirrors the look of `GitStep.notFoundState` so
/// the experience stays consistent across both entry points.
struct GitNotFoundView: View {
    @Environment(GitEnvironment.self) private var gitEnvironment
    @Environment(\.appTheme) private var theme
    @State private var isInstalling = false

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xxl) {
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                    .fill(theme.palette.warn.opacity(0.15))
                    .frame(width: 64, height: 64)
                GFIcon(kind: .warn, size: 28, stroke: theme.palette.warn)
            }
            VStack(spacing: DesignTokens.Spacing.sm) {
                Text("Git is required")
                    .font(AppFont.sans(16, weight: .semibold))
                    .foregroundStyle(theme.palette.fg1)
                Text("gitForge needs the `git` command-line tool. Install the Xcode Command Line Tools to continue.")
                    .font(AppFont.sans(12))
                    .foregroundStyle(theme.palette.fg3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            HStack(spacing: DesignTokens.Spacing.md) {
                GFButton(
                    title: isInstalling ? "Installing…" : "Install Command Line Tools",
                    style: .primary,
                    disabled: isInstalling,
                    action: installCommandLineTools
                )
                GFButton(title: "Recheck") {
                    Task { await gitEnvironment.refreshGitInstallation() }
                }
            }
        }
        .padding(DesignTokens.Spacing.xxxhuge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.palette.bg2)
    }

    private func installCommandLineTools() {
        isInstalling = true
        Task {
            await Task.detached {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
                process.arguments = ["--install"]
                try? process.run()
                process.waitUntilExit()
            }.value
            isInstalling = false
            await gitEnvironment.refreshGitInstallation()
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    GitNotFoundView()
        .previewAppState(.previewMissingGit)
        .frame(width: 720, height: 480)
        .appTheme(theme)
}
