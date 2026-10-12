import SwiftUI

/// Captures the two `git config --global` knobs that hurt most when wrong:
/// `init.defaultBranch` (so new repos don't start on `master`) and a default
/// clone directory persisted into the same `AppStorage` key `CloneSheet`
/// reads. Skippable — both have sensible defaults.
struct DefaultsStep: View {
    @Bindable var state: OnboardingState
    let onPickDirectory: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var branchChoice: BranchChoice = .main

    enum BranchChoice: Hashable { case main, master, custom }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            branchCard
            directoryCard
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { syncBranchChoice() }
        .onChange(of: branchChoice) { _, choice in
            switch choice {
            case .main:    state.defaultBranch = "main"
            case .master:  state.defaultBranch = "master"
            case .custom:  break
            }
        }
    }

    private var branchCard: some View {
        card {
            VStack(alignment: .leading, spacing: Spacing.s8) {
                Text("Default branch for new repositories")
                    .textRole(.body, weight: .semibold)
                    .foregroundStyle(theme.colors.textPrimary)
                Text("Used by `git init` and any clone that creates a fresh local branch.")
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textSecondary)
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
            VStack(alignment: .leading, spacing: Spacing.s8) {
                Text("Default clone directory")
                    .textRole(.body, weight: .semibold)
                    .foregroundStyle(theme.colors.textPrimary)
                Text("Where the Clone screen suggests putting new repositories.")
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            HStack(spacing: Spacing.s8) {
                GFTextField(placeholder: "~/code", text: $state.cloneDirectory)
                GFButton(title: "Choose…", action: onPickDirectory)
            }
        }
    }

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            content()
        }
        .padding(Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card).fill(theme.colors.bgElevated))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(theme.colors.separator, lineWidth: 1))
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
        .padding(Spacing.s48)
        .frame(width: 720, height: 600)
        .background(theme.colors.bgContent)
        .appTheme(theme)
}
