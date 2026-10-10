import SwiftUI

/// Glass card at the bottom of History while a dragged branch hovers a drop
/// target: what the drop will do, and how to cancel.
struct BranchDropHUD: View {
    let intent: BranchDropIntent

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: Spacing.s12) {
            Image(systemName: intent.systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.colors.accent)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: Radius.control).fill(theme.colors.accentSoft))
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text(intent.title)
                    .textRole(.body, weight: .semibold)
                    .foregroundStyle(theme.colors.textPrimary)
                Text(intent.detail)
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Esc cancels")
                    .textRole(.caption)
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
        .padding(Spacing.s12)
        .frame(maxWidth: 420, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.popover))
        .shadow(color: theme.colors.shadow, radius: 18, y: 8)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Drag preview for a branch chip: a solid capsule with the branch glyph.
struct BranchDragGhost: View {
    let name: String
    let isCurrent: Bool

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: Spacing.s6) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 11, weight: .semibold))
            Text(name)
                .font(AppFont.font(.mono, weight: .semibold, monoFamily: theme.monoFont))
                .lineLimit(1)
        }
        .foregroundStyle(isCurrent ? theme.colors.accentOnFill : theme.colors.textPrimary)
        .padding(.horizontal, Spacing.s12)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: Radius.control).fill(isCurrent ? theme.colors.accentFill : theme.colors.bgElevated))
        .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(theme.colors.strokeControl, lineWidth: 1))
        .rotationEffect(.degrees(-2))
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(spacing: 24) {
        BranchDragGhost(name: "feature/lane-legend", isCurrent: false)
        BranchDropHUD(intent: .branch(name: "main"))
        BranchDropHUD(intent: .commit(shortSha: "a3f9c21", subject: "Render lanes through Metal"))
    }
    .padding(40)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
