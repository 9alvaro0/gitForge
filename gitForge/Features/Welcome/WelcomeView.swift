import SwiftUI
import AppKit

/// Empty-state shown when no repository is active. Lives in the redesigned
/// shell, alongside the rest of the section views.
struct WelcomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 16) {
            GFIcon(kind: .folder, size: 48, stroke: theme.palette.fg4)
            Text("No repository open")
                .font(AppFont.sans(16, weight: .semibold))
                .foregroundStyle(theme.palette.fg1)
            Text("Open an existing repository to start exploring its history.")
                .font(AppFont.sans(12))
                .foregroundStyle(theme.palette.fg3)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                ToolButton(.folder, label: "Open repository…", primary: true) {
                    Task { await appState.presentOpenRepositoryPanel() }
                }
                ToolButton(.clone, label: "Clone…") {
                    appState.workspaceSection = .clone
                }
            }
            .padding(.top, 8)
            recentList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .background(theme.palette.bg2)
    }

    @ViewBuilder
    private var recentList: some View {
        if !appState.repositories.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("RECENT")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(theme.palette.fg3)
                ForEach(appState.repositories.prefix(5)) { repo in
                    Button {
                        Task { await appState.activate(repo) }
                    } label: {
                        HStack(spacing: 10) {
                            RepoMark(letter: orgInitial(repo))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(repo.name)
                                    .font(AppFont.sans(12, weight: .medium))
                                    .foregroundStyle(theme.palette.fg1)
                                Text(repo.path)
                                    .font(AppFont.mono(11, family: theme.monoFont))
                                    .foregroundStyle(theme.palette.fg3)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
                        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: 1))
                        .contentShape(.rect(cornerRadius: DesignTokens.Radius.md))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([repo.url])
                        }
                        Divider()
                        Button("Remove from Recents", role: .destructive) {
                            Task { await appState.removeFromRecents(repo.url) }
                        }
                    }
                }
            }
            .frame(maxWidth: 480)
            .padding(.top, 18)
        }
    }

    private func orgInitial(_ repo: Repository) -> String {
        let parent = repo.url.deletingLastPathComponent().lastPathComponent
        return String((parent.isEmpty ? repo.name : parent).prefix(1))
    }
}

#Preview("With recents") {
    @Previewable @State var theme = AppTheme()
    WelcomeView()
        .environment(AppState.preview)
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
