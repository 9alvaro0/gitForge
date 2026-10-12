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
        VStack(alignment: .leading, spacing: Spacing.s24) {
            switch gitEnvironment.gitStatus {
            case .checking:    checkingState
            case .available:   availableState
            case .notFound:    notFoundState
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        HStack(spacing: Spacing.s12) {
            ProgressView()
                .controlSize(.small)
            Text("Checking for git…")
                .textRole(.body)
                .foregroundStyle(theme.colors.textSecondary)
        }
        .padding(Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card).fill(theme.colors.bgElevated))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(theme.colors.separator, lineWidth: 1))
    }

    private var availableState: some View {
        HStack(alignment: .top, spacing: Spacing.s12) {
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.colors.ok)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: Radius.control).fill(theme.colors.okSoft))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.s4) {
                Text("Git is ready")
                    .textRole(.body, weight: .semibold)
                    .foregroundStyle(theme.colors.textPrimary)
                Text("The `git` command-line tool was found on this Mac.")
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
        .padding(Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card).fill(theme.colors.bgElevated))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(theme.colors.separator, lineWidth: 1))
    }

    private var notFoundState: some View {
        GitInstallPrompt()
    }
}

#Preview("Git available") {
    @Previewable @State var theme = AppTheme()
    GitStep(onAvailable: {})
        .previewAppState(.previewEmpty)
        .padding(Spacing.s48)
        .frame(width: 720, height: 480)
        .background(theme.colors.bgContent)
        .appTheme(theme)
}

#Preview("Git missing") {
    @Previewable @State var theme = AppTheme()
    GitStep(onAvailable: {})
        .previewAppState(.previewMissingGit)
        .padding(Spacing.s48)
        .frame(width: 720, height: 480)
        .background(theme.colors.bgContent)
        .appTheme(theme)
}
