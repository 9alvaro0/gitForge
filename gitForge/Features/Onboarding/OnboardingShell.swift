import SwiftUI

/// Chrome around an onboarding step (artboard `Onboarding`): a glass rail
/// with the steps on the left; on the right "Step N of 6", the step's
/// heading and lede, its content, and the Back / Skip / primary row.
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
        HStack(spacing: 0) {
            OnboardingRail(currentStep: currentStep)
                .frame(width: 280)
                .padding(Spacing.s8)
            GeometryReader { column in
                let gutter = LayoutMetrics.onboardingGutter(columnWidth: column.size.width)
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Spacing.s24) {
                            header
                            content()
                        }
                        .frame(maxWidth: 1000, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, gutter)
                        .padding(.top, LayoutMetrics.onboardingTop)
                        .padding(.bottom, Spacing.s24)
                    }
                    footer(gutter: gutter)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.bgWindow)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s6) {
            Text(currentStep.counter)
                .textRole(.callout, weight: .semibold)
                .foregroundStyle(theme.colors.accent)
            Text(currentStep.heading)
                .textRole(.largeTitle)
                .foregroundStyle(theme.colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(LocalizedStringKey(currentStep.lede))
                .textRole(.body)
                .foregroundStyle(theme.colors.textSecondary)
                .frame(maxWidth: 560, alignment: .leading)
        }
    }

    /// `Back` is hidden on the first step, `Skip` on the mandatory ones, and
    /// the primary button on the terminal step (it closes through its cards).
    private func footer(gutter: CGFloat) -> some View {
        HStack(spacing: Spacing.s12) {
            if currentStep.canGoBack {
                GFButton(title: "Back", action: onBack)
            }
            Spacer(minLength: 0)
            if let next = currentStep.nextLabel, !primaryLabel.isEmpty {
                Text(next)
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            if currentStep.canSkip {
                GFButton(title: "Skip", action: onSkip)
            }
            if !primaryLabel.isEmpty {
                GFButton(title: primaryBusy ? "Working…" : primaryLabel,
                         style: .primary,
                         disabled: !primaryEnabled || primaryBusy,
                         action: onPrimary)
            }
        }
        .padding(.horizontal, gutter)
        .padding(.vertical, Spacing.s20)
    }
}

/// The steps, with done / current / to-do markers that differ in shape,
/// not just colour.
private struct OnboardingRail: View {
    let currentStep: OnboardingState.Step

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s24) {
            HStack(spacing: Spacing.s8) {
                Text("gf")
                    .textRole(.body, weight: .bold)
                    .foregroundStyle(theme.colors.accentOnFill)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: Radius.control).fill(theme.colors.accentFill))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Welcome to gitForge").textRole(.headline)
                    Text("About a minute to set up")
                        .textRole(.callout)
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
            .padding(.top, Spacing.s32)
            VStack(alignment: .leading, spacing: Spacing.s4) {
                ForEach(OnboardingState.Step.allCases) { step in
                    stepRow(step)
                }
            }
            Spacer()
            Text("Everything here lives in Settings later.")
                .textRole(.caption)
                .foregroundStyle(theme.colors.textTertiary)
        }
        .padding(.horizontal, Spacing.s16)
        .padding(.bottom, Spacing.s20)
        .frame(maxHeight: .infinity, alignment: .top)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.panel))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Setup steps")
    }

    private func stepRow(_ step: OnboardingState.Step) -> some View {
        let isCurrent = step == currentStep
        let isDone = step.rawValue < currentStep.rawValue
        return HStack(spacing: Spacing.s12) {
            marker(step, isCurrent: isCurrent, isDone: isDone)
            VStack(alignment: .leading, spacing: 0) {
                Text(step.title)
                    .textRole(.body, weight: isCurrent ? .semibold : .regular)
                    .foregroundStyle(theme.colors.textPrimary)
                Text(step.railSubtitle)
                    .textRole(.caption)
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
        .padding(.horizontal, Spacing.s8)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card).fill(isCurrent ? theme.colors.fillHover : .clear))
        .accessibilityElement(children: .combine)
        .accessibilityValue(isCurrent ? "Current step" : isDone ? "Done" : "To do")
    }

    @ViewBuilder
    private func marker(_ step: OnboardingState.Step, isCurrent: Bool, isDone: Bool) -> some View {
        if isDone {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(theme.colors.bgContent)
                .frame(width: 24, height: 24)
                .background(Circle().fill(theme.colors.ok))
        } else if isCurrent {
            Text("\(step.rawValue + 1)")
                .textRole(.caption, weight: .bold)
                .foregroundStyle(theme.colors.accentOnFill)
                .frame(width: 24, height: 24)
                .background(Circle().fill(theme.colors.accentFill))
        } else {
            Text("\(step.rawValue + 1)")
                .textRole(.caption, weight: .bold)
                .foregroundStyle(theme.colors.textSecondary)
                .frame(width: 24, height: 24)
                .overlay(Circle().strokeBorder(theme.colors.strokeControl, lineWidth: 1.5))
        }
    }
}

#Preview("Shell — appearance") {
    @Previewable @State var theme = AppTheme()
    OnboardingShell(
        currentStep: .appearance,
        primaryLabel: "Continue",
        primaryEnabled: true,
        primaryBusy: false,
        onBack: {},
        onSkip: {},
        onPrimary: {}
    ) {
        Text("Step content goes here").textRole(.body)
    }
    .frame(width: 1100, height: 700)
    .appTheme(theme)
}
