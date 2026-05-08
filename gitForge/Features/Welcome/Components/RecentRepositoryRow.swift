import SwiftUI
import AppKit

/// Card row used by `WelcomeView` to surface recently opened repositories.
/// The card style (border + filled background + hover lift) is specific to
/// the welcome empty state — `SidebarRepoRow` handles the in-sidebar variant.
struct RecentRepositoryRow: View {
    let repo: Repository
    var onSelect: () -> Void
    var onRemove: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DesignTokens.Spacing.lg) {
                RepoMark(letter: orgInitial)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(repo.name)
                        .font(AppFont.sans(12, weight: .medium))
                        .foregroundStyle(theme.palette.fg1)
                    Text(repo.path)
                        .font(AppFont.mono(11, family: theme.monoFont))
                        .foregroundStyle(theme.palette.fg3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.vertical, DesignTokens.Spacing.md)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(background))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(border, lineWidth: DesignTokens.Stroke.regular))
            .contentShape(.rect(cornerRadius: DesignTokens.Radius.md))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(DesignTokens.Motion.fast, value: hovering)
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([repo.url])
            }
            Divider()
            Button("Remove from Recents", role: .destructive, action: onRemove)
        }
    }

    private var background: Color {
        hovering ? theme.palette.bg3 : theme.palette.bg1
    }

    private var border: Color {
        hovering ? theme.palette.lineStrong : theme.palette.line
    }

    private var orgInitial: String {
        let parent = repo.url.deletingLastPathComponent().lastPathComponent
        return String((parent.isEmpty ? repo.name : parent).prefix(1))
    }
}

#if DEBUG
#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(spacing: DesignTokens.Spacing.md) {
        ForEach(Repository.previewSamples) { repo in
            RecentRepositoryRow(repo: repo, onSelect: {}, onRemove: {})
        }
    }
    .frame(width: 480)
    .padding(DesignTokens.Spacing.huge)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
#endif
