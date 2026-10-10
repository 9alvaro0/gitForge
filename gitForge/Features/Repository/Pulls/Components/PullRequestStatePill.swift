import SwiftUI

/// State of a PR as a capsule with glyph and word (spec §5 status badge).
struct PullRequestStatePill: View {
    let state: PullRequest.State

    @Environment(\.appTheme) private var theme

    var body: some View {
        let (label, symbol, fg, bg) = style
        HStack(spacing: Spacing.s4) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
            Text(label)
                .textRole(.caption, weight: .semibold)
        }
        .foregroundStyle(fg)
        .padding(.horizontal, Spacing.s8)
        .frame(height: 20)
        .background(Capsule().fill(bg))
        .accessibilityElement(children: .combine)
    }

    private var style: (String, String, Color, Color) {
        let c = theme.colors
        switch state {
        case .open: return ("Open", "arrow.triangle.pull", c.ok, c.okSoft)
        case .merged: return ("Merged", "arrow.triangle.merge", c.accent, c.accentSoft)
        case .closed: return ("Closed", "xmark.circle", c.del, c.delSoft)
        case .draft: return ("Draft", "circle.dashed", c.textTertiary, c.fillControl)
        }
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
