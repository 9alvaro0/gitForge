import SwiftUI
import AppKit

struct CIPill: View {
    let ci: CIStatus
    @Environment(\.appTheme) private var theme

    var body: some View {
        let p = theme.palette
        let (fg, bg): (Color, Color) = {
            switch ci.state {
            case .success:  (p.ok,   p.ok.opacity(DesignTokens.Opacity.muted))
            case .failure:  (p.del,  p.del.opacity(DesignTokens.Opacity.muted))
            case .pending:  (p.mod,  p.mod.opacity(DesignTokens.Opacity.muted))
            case .canceled, .unknown: (p.fg3, p.bg3)
            }
        }()
        let content = HStack(spacing: DesignTokens.Spacing.xs) {
            Text("CI:")
                .font(AppFont.mono(10, weight: .bold, family: theme.monoFont))
                .foregroundStyle(fg)
            Text(ci.label)
                .font(AppFont.sans(11))
                .foregroundStyle(fg)
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).fill(bg))

        if let url = ci.webURL {
            Button { NSWorkspace.shared.open(url) } label: {
                content.contentShape(.rect(cornerRadius: DesignTokens.Radius.xs))
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(alignment: .leading, spacing: 8) {
        ForEach(Array(CIStatus.previewSamples.enumerated()), id: \.offset) { _, status in
            CIPill(ci: status)
        }
    }
    .padding()
    .appTheme(theme)
}
