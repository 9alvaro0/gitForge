import SwiftUI

/// Captures `user.name` / `user.email` (mandatory) and an optional signing
/// key. The signing field stays collapsed under a disclosure so the step
/// stays visually short for the 90% case who don't sign their commits.
struct IdentityStep: View {
    @Bindable var state: OnboardingState

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xxl) {
            heading
            card
        }
        .frame(maxWidth: .infinity)
    }

    private var heading: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                    .fill(theme.palette.accentSoft)
                    .frame(width: 56, height: 56)
                GFIcon(kind: .user, size: 26, stroke: theme.palette.accent)
            }
            .padding(.bottom, DesignTokens.Spacing.sm)
            Text("Who are you?")
                .font(AppFont.sans(18, weight: .semibold))
                .foregroundStyle(theme.palette.fg1)
            Text("git records your name and email on every commit. This writes to `~/.gitconfig` and applies to every repository.")
                .font(AppFont.sans(12))
                .foregroundStyle(theme.palette.fg3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            field(label: "Name") {
                GFTextField(placeholder: "Ada Lovelace", text: $state.name)
            }
            field(label: "Email") {
                GFTextField(placeholder: "ada@example.com", text: $state.email)
            }
            signingDisclosure
        }
        .padding(DesignTokens.Spacing.xxl)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
    }

    @ViewBuilder
    private var signingDisclosure: some View {
        if state.showSigningField {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                disclosureToggle
                field(label: "Signing key (GPG / SSH)") {
                    GFTextField(placeholder: "Key id, optional", text: $state.signingKey)
                }
            }
        } else {
            disclosureToggle
        }
    }

    private var disclosureToggle: some View {
        Button {
            withAnimation(DesignTokens.Motion.fast) {
                state.showSigningField.toggle()
            }
        } label: {
            HStack(spacing: DesignTokens.Spacing.xs) {
                GFIcon(kind: state.showSigningField ? .chevD : .chevR,
                       size: 10, stroke: theme.palette.fg3)
                Text("Advanced — signing key")
                    .font(AppFont.sans(11, weight: .medium))
                    .foregroundStyle(theme.palette.fg3)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func field<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(label)
                .font(AppFont.sans(11, weight: .medium))
                .foregroundStyle(theme.palette.fg3)
            content()
        }
    }
}

#Preview("Empty") {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var state = OnboardingState()
    IdentityStep(state: state)
        .padding(DesignTokens.Spacing.xxxhuge)
        .frame(width: 720, height: 600)
        .background(theme.palette.bg2)
        .appTheme(theme)
}

#Preview("Pre-filled") {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var state = OnboardingState.previewFilled
    IdentityStep(state: state)
        .padding(DesignTokens.Spacing.xxxhuge)
        .frame(width: 720, height: 600)
        .background(theme.palette.bg2)
        .appTheme(theme)
}
