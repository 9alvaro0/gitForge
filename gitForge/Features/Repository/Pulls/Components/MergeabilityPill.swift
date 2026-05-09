import SwiftUI

struct MergeabilityPill: View {
    let mergeable: Bool?
    @Environment(\.appTheme) private var theme

    var body: some View {
        let p = theme.palette
        let (text, fg, bg): (String, Color, Color) = {
            switch mergeable {
            case .some(true):  return ("Mergeable", p.ok, p.ok.opacity(DesignTokens.Opacity.muted))
            case .some(false): return ("Has conflicts", p.del, p.del.opacity(DesignTokens.Opacity.muted))
            case .none:        return ("Mergeability unknown", p.fg3, p.bg3)
            }
        }()
        Text(text)
            .font(AppFont.sans(11))
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .foregroundStyle(fg)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).fill(bg))
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(alignment: .leading, spacing: 8) {
        MergeabilityPill(mergeable: true)
        MergeabilityPill(mergeable: false)
        MergeabilityPill(mergeable: nil)
    }
    .padding()
    .appTheme(theme)
}
