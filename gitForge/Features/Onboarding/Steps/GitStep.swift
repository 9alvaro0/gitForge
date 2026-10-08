import SwiftUI

/// Probes the git CLI and either confirms (auto-advancing) or surfaces the
/// install prompt. Replaces the standalone `GitNotFoundView` for first-run;
/// the post-onboarding gate still uses `GitNotFoundView` directly in case
/// the user uninstalls git later.
struct GitStep: View {
    /// Fired once the probe reports `.available` so the coordinator can
    /// move past this step without the user having to click Continue.
    let onAvailable: () -> Void

    @Environment(GitEnvironment.self) private var gitEnvironment
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xxhuge) {
            switch gitEnvironment.gitStatus {
            case .checking:    checkingState
            case .available:   availableState
            case .notFound:    notFoundState
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: gitEnvironment.gitStatus) {
            if gitEnvironment.gitStatus == .available {
                // Auto-skip after a short beat so the user sees the green
                // confirmation rather than the step flashing past.
                try? await Task.sleep(for: .milliseconds(450))
                onAvailable()
            }
        }
    }

    private var checkingState: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            ProgressView()
                .controlSize(.regular)
            Text("Checking for git…")
                .font(AppFont.sans(FontSize.lg))
                .foregroundStyle(theme.palette.fg3)
        }
    }

    private var availableState: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            StatusBadge(icon: .check, tint: theme.palette.ok)
            VStack(spacing: DesignTokens.Spacing.sm) {
                Text("Git is ready")
                    .font(AppFont.sans(FontSize.xxxl, weight: .semibold))
                    .foregroundStyle(theme.palette.fg1)
                Text("The `git` command-line tool was found on this Mac.")
                    .font(AppFont.sans(FontSize.md))
                    .foregroundStyle(theme.palette.fg3)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var notFoundState: some View {
        GitInstallPrompt()
    }
}

#Preview("Git available") {
    @Previewable @State var theme = AppTheme()
    GitStep(onAvailable: {})
        .previewAppState(.previewEmpty)
        .padding(DesignTokens.Spacing.xxxhuge)
        .frame(width: 720, height: 480)
        .background(theme.palette.bg2)
        .appTheme(theme)
}

#Preview("Git missing") {
    @Previewable @State var theme = AppTheme()
    GitStep(onAvailable: {})
        .previewAppState(.previewMissingGit)
        .padding(DesignTokens.Spacing.xxxhuge)
        .frame(width: 720, height: 480)
        .background(theme.palette.bg2)
        .appTheme(theme)
}
