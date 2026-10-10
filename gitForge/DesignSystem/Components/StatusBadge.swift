import SwiftUI

/// Large rounded status mark used by full-screen states (onboarding, gates):
/// an icon in `tint` over a soft fill of the same colour.
struct StatusBadge: View {
    let icon: GFIconKind
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.card)
                .fill(tint.opacity(0.16))
                .frame(width: DesignTokens.IconSize.badge, height: DesignTokens.IconSize.badge)
            GFIcon(kind: icon, size: DesignTokens.IconSize.badgeGlyph, stroke: tint)
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    HStack(spacing: DesignTokens.Spacing.xl) {
        StatusBadge(icon: .check, tint: theme.palette.ok)
        StatusBadge(icon: .warn, tint: theme.palette.warn)
    }
    .padding()
    .background(theme.palette.bg2)
    .appTheme(theme)
}
