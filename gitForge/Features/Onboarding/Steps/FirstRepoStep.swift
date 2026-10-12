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
        VStack(alignment: .leading, spacing: Spacing.s12) {
            actionCard(symbol: "folder",
                       title: "Open a folder",
                       subtitle: "Add an existing local git repository.",
                       cta: "Choose folder…",
                       action: onOpenLocal)
            actionCard(symbol: "square.and.arrow.down",
                       title: "Clone from URL",
                       subtitle: "Bring a repository down from any git remote (HTTPS or SSH).",
                       cta: "Open Clone…",
                       action: onClone)
            actionCard(symbol: "cloud",
                       title: "Connect GitHub or GitLab",
                       subtitle: "Browse your repositories and clone them in two clicks.",
                       cta: "Browse providers…",
                       action: onConnect)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionCard(symbol: String,
                            title: String,
                            subtitle: String,
                            cta: String,
                            action: @escaping () -> Void) -> some View {
        HStack(spacing: Spacing.s12) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(theme.colors.accent)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: Radius.control).fill(theme.colors.accentSoft))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text(title)
                    .textRole(.body, weight: .semibold)
                    .foregroundStyle(theme.colors.textPrimary)
                Text(subtitle)
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            Spacer(minLength: 0)
            GFButton(title: cta, action: action)
        }
        .padding(Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card).fill(theme.colors.bgElevated))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(theme.colors.separator, lineWidth: 1))
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    FirstRepoStep(onOpenLocal: {}, onClone: {}, onConnect: {})
        .padding(Spacing.s48)
        .frame(width: 720, height: 600)
        .background(theme.colors.bgContent)
        .appTheme(theme)
}
