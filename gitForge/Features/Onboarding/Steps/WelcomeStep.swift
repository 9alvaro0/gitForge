import SwiftUI

/// First impression: app name, tagline, and a short list of what the app
/// actually does. The bullet rows replace the old empty-state's single line
/// of body copy and tell the user what to expect from the rest of the shell.
struct WelcomeStep: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xxhuge) {
            hero
            featureList
        }
        .frame(maxWidth: .infinity)
    }

    private var hero: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                    .fill(theme.palette.accentSoft)
                    .frame(width: 64, height: 64)
                GFIcon(kind: .branch, size: 32, stroke: theme.palette.accent)
            }
            VStack(spacing: DesignTokens.Spacing.sm) {
                Text("Welcome to gitForge")
                    .font(AppFont.sans(20, weight: .semibold))
                    .foregroundStyle(theme.palette.fg1)
                Text("A native macOS git client built around fast history navigation, fluid diffs, and a quiet UI.")
                    .font(AppFont.sans(13))
                    .foregroundStyle(theme.palette.fg3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            featureRow(icon: .graph, title: "History graph", subtitle: "Branches, merges, and tags rendered as you scroll.")
            featureRow(icon: .diff,  title: "Side-by-side diffs", subtitle: "Unified or split, with the same syntax highlighter as your editor.")
            featureRow(icon: .pr,    title: "Pull requests inline", subtitle: "Browse GitHub and GitLab PRs without leaving the app.")
            featureRow(icon: .stash, title: "Stashes and conflicts", subtitle: "First-class drill-in for both — no terminal trips required.")
        }
        .padding(DesignTokens.Spacing.xxl)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
    }

    private func featureRow(icon: GFIconKind, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.lg) {
            GFIcon(kind: icon, size: 16, stroke: theme.palette.fg2)
                .frame(width: 20, height: 20)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(title)
                    .font(AppFont.sans(12, weight: .semibold))
                    .foregroundStyle(theme.palette.fg1)
                Text(subtitle)
                    .font(AppFont.sans(11.5))
                    .foregroundStyle(theme.palette.fg3)
            }
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    WelcomeStep()
        .padding(DesignTokens.Spacing.xxxhuge)
        .frame(width: 720, height: 540)
        .background(theme.palette.bg2)
        .appTheme(theme)
}
