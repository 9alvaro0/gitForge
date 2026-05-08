import SwiftUI

/// Empty-state shown when no repository is active. Lives in the redesigned
/// shell, alongside the rest of the section views.
struct WelcomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xxxl) {
            GFIcon(kind: .folder, size: 40, stroke: theme.palette.fg4)
            Text("No repository open")
                .font(AppFont.sans(14, weight: .semibold))
                .foregroundStyle(theme.palette.fg1)
            Text("Open an existing repository to start exploring its history.")
                .font(AppFont.sans(12))
                .foregroundStyle(theme.palette.fg3)
                .multilineTextAlignment(.center)
            HStack(spacing: DesignTokens.Spacing.md) {
                GFButton(title: "Open repository…", style: .primary) {
                    Task { await appState.presentOpenRepositoryPanel() }
                }
                GFButton(title: "Clone…") {
                    appState.ui.workspaceSection = .clone
                }
            }
            .padding(.top, DesignTokens.Spacing.md)
            recentList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignTokens.Spacing.xxxhuge)
        .background(theme.palette.bg2)
    }

    @ViewBuilder
    private var recentList: some View {
        if !appState.catalog.repositories.isEmpty {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                Text("RECENT")
                    .font(.system(size: FontSize.footnote, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(theme.palette.fg3)
                ForEach(appState.catalog.repositories.prefix(5)) { repo in
                    RecentRepositoryRow(
                        repo: repo,
                        onSelect: { Task { await appState.activate(repo) } },
                        onRemove: { Task { await appState.catalog.remove(repo.url) } }
                    )
                }
            }
            .frame(maxWidth: 480)
            .padding(.top, DesignTokens.Spacing.xxxxl)
        }
    }
}

#if DEBUG
#Preview("With recents") {
    @Previewable @State var theme = AppTheme()
    WelcomeView()
        .previewAppState(.preview)
        .frame(width: 900, height: 600)
        .appTheme(theme)
}

#Preview("No recents") {
    @Previewable @State var theme = AppTheme()
    WelcomeView()
        .environment(AppState())
        .frame(width: 900, height: 600)
        .appTheme(theme)
}
#endif
