import SwiftUI

/// Chrome around an onboarding step: top progress strip + bottom navigation
/// row. Steps render their own content in the middle. Mirrors the layout of
/// `ContentHeader` + a `ScrollView` body found across the rest of the app,
/// but tuned for a single centered column instead of a sidebar+detail split.
struct OnboardingShell<Content: View>: View {
    let currentStep: OnboardingState.Step
    let primaryLabel: String
    let primaryEnabled: Bool
    let primaryBusy: Bool
    let onBack: () -> Void
    let onSkip: () -> Void
    let onPrimary: () -> Void
    @ViewBuilder var content: () -> Content

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.none) {
            OnboardingHeader(currentStep: currentStep)
            ScrollView {
                content()
                    .frame(maxWidth: 540)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignTokens.Spacing.xxhuge)
                    .padding(.horizontal, DesignTokens.Spacing.xxxhuge)
            }
            OnboardingFooter(
                showBack: currentStep.canGoBack,
                showSkip: currentStep.canSkip,
                primaryLabel: primaryLabel,
                primaryEnabled: primaryEnabled,
                primaryBusy: primaryBusy,
                onBack: onBack,
                onSkip: onSkip,
                onPrimary: onPrimary
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.palette.bg2)
    }
}

/// App-name badge on the left, step counter and progress dots on the right.
/// The badge intentionally avoids a heavy logo — the same `.branch` glyph
/// used in the sidebar ties the onboarding to the rest of the chrome.
private struct OnboardingHeader: View {
    let currentStep: OnboardingState.Step

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xxxl) {
            HStack(spacing: DesignTokens.Spacing.md) {
                GFIcon(kind: .branch, size: 16, stroke: theme.palette.accent)
                Text("gitForge")
                    .font(AppFont.sans(13, weight: .semibold))
                    .foregroundStyle(theme.palette.fg1)
            }
            Spacer(minLength: 0)
            HStack(spacing: DesignTokens.Spacing.lg) {
                Text("Step \(currentStep.rawValue + 1) of \(OnboardingState.Step.allCases.count)")
                    .font(AppFont.sans(11))
                    .foregroundStyle(theme.palette.fg3)
                ProgressDots(currentStep: currentStep)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xxxxl)
        .padding(.vertical, DesignTokens.Spacing.xxl)
        .frame(maxWidth: .infinity)
        .background(theme.palette.bg2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.palette.lineStrong).frame(height: DesignTokens.Stroke.regular)
        }
    }
}

private struct ProgressDots: View {
    let currentStep: OnboardingState.Step

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            ForEach(OnboardingState.Step.allCases) { step in
                Circle()
                    .fill(color(for: step))
                    .frame(width: dotSize(for: step), height: dotSize(for: step))
                    .animation(DesignTokens.Motion.fast, value: currentStep)
            }
        }
    }

    private func color(for step: OnboardingState.Step) -> Color {
        if step == currentStep { return theme.palette.accent }
        if step.rawValue < currentStep.rawValue { return theme.palette.fg3 }
        return theme.palette.fg4
    }

    private func dotSize(for step: OnboardingState.Step) -> CGFloat {
        step == currentStep ? 8 : 6
    }
}

/// Sticky footer with the three nav controls. `Back` is hidden on the
/// first step, `Skip` on the mandatory ones (welcome / git / identity),
/// and `Continue` is omitted entirely on the terminal step (FirstRepo
/// closes the flow via its own card actions).
private struct OnboardingFooter: View {
    let showBack: Bool
    let showSkip: Bool
    let primaryLabel: String
    let primaryEnabled: Bool
    let primaryBusy: Bool
    let onBack: () -> Void
    let onSkip: () -> Void
    let onPrimary: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            if showBack {
                GFButton(title: "Back", action: onBack)
            }
            Spacer(minLength: 0)
            if showSkip {
                GFButton(title: "Skip", action: onSkip)
            }
            if !primaryLabel.isEmpty {
                GFButton(
                    title: primaryBusy ? "Working…" : primaryLabel,
                    style: .primary,
                    disabled: !primaryEnabled || primaryBusy,
                    action: onPrimary
                )
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xxxxl)
        .padding(.vertical, DesignTokens.Spacing.xxl)
        .frame(maxWidth: .infinity)
        .background(theme.palette.bg2)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.palette.lineStrong).frame(height: DesignTokens.Stroke.regular)
        }
    }
}

#Preview("Shell — middle step") {
    @Previewable @State var theme = AppTheme()
    OnboardingShell(
        currentStep: .identity,
        primaryLabel: "Continue",
        primaryEnabled: true,
        primaryBusy: false,
        onBack: {},
        onSkip: {},
        onPrimary: {}
    ) {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Text("Step content goes here")
                .font(AppFont.sans(14))
                .foregroundStyle(theme.palette.fg2)
        }
    }
    .frame(width: 820, height: 560)
    .appTheme(theme)
}

#Preview("Shell — first step (no Back)") {
    @Previewable @State var theme = AppTheme()
    OnboardingShell(
        currentStep: .welcome,
        primaryLabel: "Get started",
        primaryEnabled: true,
        primaryBusy: false,
        onBack: {},
        onSkip: {},
        onPrimary: {}
    ) {
        Text("Welcome content")
            .font(AppFont.sans(14))
    }
    .frame(width: 820, height: 560)
    .appTheme(theme)
}
