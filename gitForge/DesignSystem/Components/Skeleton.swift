import SwiftUI

/// `.gf-skeleton` — placeholder shimmer for loading states. Render the row
/// or field structure with realistic dummy values, then apply `.skeleton(true)`
/// to the container. Uses SwiftUI's `redacted(.placeholder)` to draw grey
/// shapes from the underlying text widths, plus a gentle opacity pulse.
///
/// Reserve this for content with predictable shape (lists, fields).
/// Use `ProgressView` for user-initiated actions (clone, fetch, push)
/// where the data has no shape yet.
struct SkeletonModifier: ViewModifier {
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if isActive {
            content
                .redacted(reason: .placeholder)
                .allowsHitTesting(false)
                // With Reduce Motion the placeholder holds still at the
                // middle of its pulse instead of breathing forever.
                .phaseAnimator(reduceMotion ? [0.7] : [0.45, 1.0]) { view, phase in
                    view.opacity(phase)
                } animation: { _ in
                    Motion.slow
                }
                // The placeholder is built from realistic *fake* rows; without
                // this VoiceOver reads the dummy text as if it were content.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Loading")
                .transition(.opacity)
        } else {
            content
                .transition(.opacity)
        }
    }
}

extension View {
    /// Renders the view as a shimmering placeholder when `isActive` is true.
    /// When false, the view is returned unchanged.
    func skeleton(_ isActive: Bool) -> some View {
        modifier(SkeletonModifier(isActive: isActive))
    }
}

#Preview("Skeleton — rows") {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var loading = true

    VStack(alignment: .leading, spacing: Spacing.s12) {
        Toggle("Loading", isOn: $loading)
            .toggleStyle(.switch)
            .padding(.horizontal, Spacing.s20)

        VStack(spacing: Spacing.s8) {
            ForEach(0..<5, id: \.self) { _ in
                HStack(spacing: Spacing.s12) {
                    Text("OPEN")
                        .textRole(.monoSmall, weight: .bold)
                        .padding(.horizontal, Spacing.s6).padding(.vertical, Spacing.s2)
                        .background(RoundedRectangle(cornerRadius: Radius.badge).fill(theme.colors.fillControl))
                    VStack(alignment: .leading, spacing: Spacing.s4) {
                        Text("Add merge request integration")
                            .textRole(.body, weight: .medium)
                            .foregroundStyle(theme.colors.textPrimary)
                        Text("@author · feat/branch-name → main · 2h ago")
                            .textRole(.callout)
                            .foregroundStyle(theme.colors.textTertiary)
                    }
                    Spacer()
                }
                .padding(.horizontal, Spacing.s16).padding(.vertical, Spacing.s12)
                .background(RoundedRectangle(cornerRadius: Radius.controlSmall).fill(theme.colors.bgElevated))
                .overlay(RoundedRectangle(cornerRadius: Radius.controlSmall).stroke(theme.colors.separator, lineWidth: 1))
            }
        }
        .padding(Spacing.s20)
        .skeleton(loading)
    }
    .frame(width: 640, height: 360)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
