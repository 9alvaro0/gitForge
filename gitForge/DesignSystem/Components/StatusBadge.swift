import SwiftUI

/// Large rounded status mark used by full-screen states (onboarding, gates):
/// an icon in `tint` over a soft fill of the same colour.
struct StatusBadge: View {
    /// SF Symbol name.
    let symbol: String
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.card)
                .fill(tint.opacity(0.16))
                .frame(width: 64, height: 64)
            Image(systemName: symbol)
                .font(.system(size: 28 * 0.8, weight: .medium))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    HStack(spacing: Spacing.s12) {
        StatusBadge(symbol: "checkmark", tint: theme.colors.ok)
        StatusBadge(symbol: "exclamationmark.triangle", tint: theme.colors.warn)
    }
    .padding()
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
