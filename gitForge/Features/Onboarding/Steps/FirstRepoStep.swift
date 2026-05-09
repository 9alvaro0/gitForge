import SwiftUI

/// Terminal step. Three cards covering the practical entry points; tapping
/// any of them either opens a folder picker or routes the shell into the
/// matching workspace section. The footer's `Skip` button leaves the user
/// on the empty `WelcomeView` if they'd rather add a repo later.
struct FirstRepoStep: View {
    let onOpenLocal: () -> Void
    let onClone: () -> Void
    let onConnect: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xxl) {
            heading
            VStack(spacing: DesignTokens.Spacing.lg) {
                actionCard(icon: .folder,
                           title: "Open a folder",
                           subtitle: "Add an existing local git repository.",
                           cta: "Choose folder…",
                           action: onOpenLocal)
                actionCard(icon: .clone,
                           title: "Clone from URL",
                           subtitle: "Bring a repository down from any git remote (HTTPS or SSH).",
                           cta: "Open Clone…",
                           action: onClone)
                actionCard(icon: .cloud,
                           title: "Connect GitHub or GitLab",
                           subtitle: "Browse your repositories and clone them in two clicks.",
                           cta: "Browse providers…",
                           action: onConnect)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var heading: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                    .fill(theme.palette.accentSoft)
                    .frame(width: 56, height: 56)
                GFIcon(kind: .folder, size: 26, stroke: theme.palette.accent)
            }
            .padding(.bottom, DesignTokens.Spacing.sm)
            Text("Add your first repository")
                .font(AppFont.sans(18, weight: .semibold))
                .foregroundStyle(theme.palette.fg1)
            Text("Pick how you want to get started — or skip and add one later from the sidebar.")
                .font(AppFont.sans(12))
                .foregroundStyle(theme.palette.fg3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
    }

    private func actionCard(icon: GFIconKind,
                            title: String,
                            subtitle: String,
                            cta: String,
                            action: @escaping () -> Void) -> some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .fill(theme.palette.bg3)
                    .frame(width: 40, height: 40)
                GFIcon(kind: icon, size: 20, stroke: theme.palette.fg2)
            }
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(title)
                    .font(AppFont.sans(13, weight: .semibold))
                    .foregroundStyle(theme.palette.fg1)
                Text(subtitle)
                    .font(AppFont.sans(11.5))
                    .foregroundStyle(theme.palette.fg3)
            }
            Spacer(minLength: 0)
            GFButton(title: cta, action: action)
        }
        .padding(DesignTokens.Spacing.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    FirstRepoStep(onOpenLocal: {}, onClone: {}, onConnect: {})
        .padding(DesignTokens.Spacing.xxxhuge)
        .frame(width: 720, height: 600)
        .background(theme.palette.bg2)
        .appTheme(theme)
}
