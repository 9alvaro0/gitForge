import SwiftUI

/// Captures `user.name` / `user.email` (mandatory) and an optional signing
/// key. The signing field stays collapsed under a disclosure so the step
/// stays visually short for the 90% case who don't sign their commits.
struct IdentityStep: View {
    @Bindable var state: OnboardingState

    @Environment(\.appTheme) private var theme

    var body: some View {
        card
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            field(label: String(localized: "Name")) {
                GFTextField(placeholder: "Ada Lovelace", text: $state.name)
            }
            field(label: String(localized: "Email")) {
                GFTextField(placeholder: "ada@example.com", text: $state.email)
            }
            signingDisclosure
        }
        .padding(Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card).fill(theme.colors.bgElevated))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(theme.colors.separator, lineWidth: 1))
    }

    @ViewBuilder
    private var signingDisclosure: some View {
        if state.showSigningField {
            VStack(alignment: .leading, spacing: Spacing.s8) {
                disclosureToggle
                field(label: String(localized: "Signing key (GPG / SSH)")) {
                    GFTextField(placeholder: String(localized: "Key id, optional"), text: $state.signingKey)
                }
            }
        } else {
            disclosureToggle
        }
    }

    private var disclosureToggle: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                state.showSigningField.toggle()
            }
        } label: {
            HStack(spacing: Spacing.s4) {
                Image(systemName: state.showSigningField ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.colors.textTertiary)
                    .accessibilityHidden(true)
                Text("Advanced — signing key")
                    .textRole(.callout, weight: .medium)
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func field<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            Text(label)
                .textRole(.callout, weight: .medium)
                .foregroundStyle(theme.colors.textSecondary)
            content()
        }
    }
}

#Preview("Empty") {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var state = OnboardingState()
    IdentityStep(state: state)
        .padding(Spacing.s48)
        .frame(width: 720, height: 600)
        .background(theme.colors.bgContent)
        .appTheme(theme)
}

#Preview("Pre-filled") {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var state = OnboardingState.previewFilled
    IdentityStep(state: state)
        .padding(Spacing.s48)
        .frame(width: 720, height: 600)
        .background(theme.colors.bgContent)
        .appTheme(theme)
}
