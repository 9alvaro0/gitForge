import SwiftUI

struct PullRequestStatePill: View {
    let state: PullRequest.State
    @Environment(\.appTheme) private var theme

    var body: some View {
        let p = theme.palette
        let (label, fg, bg): (String, Color, Color) = {
            switch state {
            case .open:   return ("OPEN",   p.ok,   p.ok.opacity(DesignTokens.Opacity.muted))
            case .merged: return ("MERGED", p.info, p.info.opacity(DesignTokens.Opacity.muted))
            case .closed: return ("CLOSED", p.del,  p.del.opacity(DesignTokens.Opacity.muted))
            case .draft:  return ("DRAFT",  p.fg3,  p.bg3)
            }
        }()
        Text(label)
            .font(AppFont.mono(10, weight: .bold, family: theme.monoFont))
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .foregroundStyle(fg)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).fill(bg))
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    HStack(spacing: 8) {
        PullRequestStatePill(state: .open)
        PullRequestStatePill(state: .merged)
        PullRequestStatePill(state: .closed)
        PullRequestStatePill(state: .draft)
    }
    .padding()
    .appTheme(theme)
}
