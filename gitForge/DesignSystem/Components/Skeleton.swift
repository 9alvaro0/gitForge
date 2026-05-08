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

    func body(content: Content) -> some View {
        if isActive {
            content
                .redacted(reason: .placeholder)
                .allowsHitTesting(false)
                .phaseAnimator([0.45, 1.0]) { view, phase in
                    view.opacity(phase)
                } animation: { _ in
                    .easeInOut(duration: 0.9)
                }
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

    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
        Toggle("Loading", isOn: $loading)
            .toggleStyle(.switch)
            .padding(.horizontal, DesignTokens.Spacing.xxxxl)

        VStack(spacing: DesignTokens.Spacing.md) {
            ForEach(0..<5, id: \.self) { _ in
                HStack(spacing: DesignTokens.Spacing.xl) {
                    Text("OPEN")
                        .font(AppFont.mono(10, weight: .bold, family: theme.monoFont))
                        .padding(.horizontal, DesignTokens.Spacing.sm).padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).fill(theme.palette.bg3))
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                        Text("Add merge request integration")
                            .font(AppFont.sans(13, weight: .medium))
                            .foregroundStyle(theme.palette.fg1)
                        Text("@author · feat/branch-name → main · 2h ago")
                            .font(AppFont.sans(12))
                            .foregroundStyle(theme.palette.fg3)
                    }
                    Spacer()
                }
                .padding(.horizontal, DesignTokens.Spacing.xxl).padding(.vertical, DesignTokens.Spacing.lg)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
            }
        }
        .padding(DesignTokens.Spacing.xxxxl)
        .skeleton(loading)
    }
    .frame(width: 640, height: 360)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
