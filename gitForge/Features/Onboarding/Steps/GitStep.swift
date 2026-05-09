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
    @State private var isInstalling = false

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
                .font(AppFont.sans(13))
                .foregroundStyle(theme.palette.fg3)
        }
    }

    private var availableState: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            statusBadge(icon: .check, tint: theme.palette.ok, soft: theme.palette.ok.opacity(0.15))
            VStack(spacing: DesignTokens.Spacing.sm) {
                Text("Git is ready")
                    .font(AppFont.sans(16, weight: .semibold))
                    .foregroundStyle(theme.palette.fg1)
                Text("The `git` command-line tool was found on this Mac.")
                    .font(AppFont.sans(12))
                    .foregroundStyle(theme.palette.fg3)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var notFoundState: some View {
        VStack(spacing: DesignTokens.Spacing.xxl) {
            statusBadge(icon: .warn, tint: theme.palette.warn, soft: theme.palette.warn.opacity(0.15))
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
    }

    private func statusBadge(icon: GFIconKind, tint: Color, soft: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                .fill(soft)
                .frame(width: 64, height: 64)
            GFIcon(kind: icon, size: 28, stroke: tint)
        }
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
