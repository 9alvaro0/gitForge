import SwiftUI

/// First impression: a short list of what the app actually does. The shell
/// renders the step number, heading and lede above this content, so only the
/// feature card lives here.
struct WelcomeStep: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        featureList
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            featureRow(symbol: "point.3.connected.trianglepath.dotted", title: "History graph", subtitle: "Branches, merges, and tags rendered as you scroll.")
            featureRow(symbol: "plus.forwardslash.minus", title: "Side-by-side diffs", subtitle: "Unified or split, with the same syntax highlighter as your editor.")
            featureRow(symbol: "arrow.triangle.pull", title: "Pull requests inline", subtitle: "Browse GitHub and GitLab PRs without leaving the app.")
            featureRow(symbol: "tray.full", title: "Stashes and conflicts", subtitle: "First-class drill-in for both — no terminal trips required.")
        }
        .padding(Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card).fill(theme.colors.bgElevated))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(theme.colors.separator, lineWidth: 1))
    }

    private func featureRow(symbol: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.s12) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(theme.colors.textSecondary)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text(title)
                    .textRole(.body, weight: .semibold)
                    .foregroundStyle(theme.colors.textPrimary)
                Text(subtitle)
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    WelcomeStep()
        .padding(Spacing.s48)
        .frame(width: 720, height: 540)
        .background(theme.colors.bgContent)
        .appTheme(theme)
}
