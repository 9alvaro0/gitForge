import SwiftUI

/// Captures the two `git config --global` knobs that hurt most when wrong:
/// `init.defaultBranch` (so new repos don't start on `master`) and a default
/// clone directory persisted into the same `AppStorage` key `CloneView`
/// reads. Skippable — both have sensible defaults.
struct DefaultsStep: View {
    @Bindable var state: OnboardingState
    let onPickDirectory: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var branchChoice: BranchChoice = .main

    enum BranchChoice: Hashable { case main, master, custom }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xxl) {
            heading
            VStack(spacing: DesignTokens.Spacing.lg) {
                branchCard
                directoryCard
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { syncBranchChoice() }
        .onChange(of: branchChoice) { _, choice in
            switch choice {
            case .main:    state.defaultBranch = "main"
            case .master:  state.defaultBranch = "master"
            case .custom:  break
            }
        }
    }

    private var heading: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                    .fill(theme.palette.accentSoft)
                    .frame(width: 56, height: 56)
                GFIcon(kind: .settings, size: 26, stroke: theme.palette.accent)
            }
            .padding(.bottom, DesignTokens.Spacing.sm)
            Text("Defaults")
                .font(AppFont.sans(18, weight: .semibold))
                .foregroundStyle(theme.palette.fg1)
            Text("Two preferences that pay off later. You can change them anytime in Settings.")
                .font(AppFont.sans(12))
                .foregroundStyle(theme.palette.fg3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
    }

    private var branchCard: some View {
        card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text("Default branch for new repositories")
                    .font(AppFont.sans(12, weight: .semibold))
                    .foregroundStyle(theme.palette.fg1)
                Text("Used by `git init` and any clone that creates a fresh local branch.")
                    .font(AppFont.sans(11))
                    .foregroundStyle(theme.palette.fg3)
            }
            SegmentedControl<BranchChoice>(
                [(.main, "main"), (.master, "master"), (.custom, "Custom")],
                selection: $branchChoice
            )
            .frame(maxWidth: 320, alignment: .leading)
            if branchChoice == .custom {
                GFTextField(placeholder: "trunk, develop…", text: $state.defaultBranch)
                    .frame(maxWidth: 320)
            }
        }
    }

    private var directoryCard: some View {
        card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text("Default clone directory")
                    .font(AppFont.sans(12, weight: .semibold))
                    .foregroundStyle(theme.palette.fg1)
                Text("Where the Clone screen suggests putting new repositories.")
                    .font(AppFont.sans(11))
                    .foregroundStyle(theme.palette.fg3)
            }
            HStack(spacing: DesignTokens.Spacing.sm) {
                GFTextField(placeholder: "~/code", text: $state.cloneDirectory)
                GFButton(title: "Choose…", action: onPickDirectory)
            }
        }
    }

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            content()
        }
        .padding(DesignTokens.Spacing.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
    }

    /// Maps the persisted string back into a segmented choice when the
    /// step appears (covers the "user pressed Back from later step" path).
    private func syncBranchChoice() {
        switch state.defaultBranch {
        case "main":    branchChoice = .main
        case "master":  branchChoice = .master
        default:        branchChoice = .custom
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var state = OnboardingState.previewFilled
    DefaultsStep(state: state, onPickDirectory: {})
        .padding(DesignTokens.Spacing.xxxhuge)
        .frame(width: 720, height: 600)
        .background(theme.palette.bg2)
        .appTheme(theme)
}
