import SwiftUI

/// `.gf-repo` row inside the sidebar repository list.
struct SidebarRepoRow: View {
    let repository: Repository
    let org: String
    let branch: String?
    let ahead: Int
    let behind: Int
    let dirty: Int
    var loaded: Bool = true
    let isCurrent: Bool
    let onSelect: () -> Void
    var onRemove: (() -> Void)? = nil
    var onRevealInFinder: (() -> Void)? = nil

    @Environment(\.appTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DesignTokens.Spacing.lg) {
                RepoMark(letter: String(org.prefix(1)))
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.hairline) {
                    Text(repository.name)
                        .font(AppFont.sans(12, weight: .medium))
                        .foregroundStyle(theme.palette.fg1)
                        .lineLimit(1)
                    if let branch {
                        Text(branch)
                            .font(AppFont.mono(10.5, family: theme.monoFont))
                            .foregroundStyle(theme.palette.fg3)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                StatusPills(ahead: ahead, behind: behind, dirty: dirty, loaded: loaded)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .frame(height: DesignTokens.Sidebar.repoRow)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(rowBackground))
            .contentShape(.rect(cornerRadius: DesignTokens.Radius.md))
            .padding(.horizontal, DesignTokens.Spacing.sm)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            if let onRevealInFinder {
                Button("Reveal in Finder", action: onRevealInFinder)
            }
            if let onRemove {
                Divider()
                // Not destructive: removing from the recents list neither
                // deletes the repo nor loses any data. Marking it destructive
                // wrongly tells VoiceOver "this is dangerous" and red-tints
                // the menu item on macOS.
                Button("Remove from Recents", action: onRemove)
            }
        }
    }

    private var rowBackground: Color {
        if isCurrent { return theme.palette.bg4 }
        return hovering ? theme.palette.bg3 : .clear
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    let samples = Repository.previewSamples
    VStack(spacing: DesignTokens.Spacing.hairline) {
        ForEach(samples) { repo in
            let isCurrent = repo.id == samples.first?.id
            let status: RepoStatusSnapshot = isCurrent ? .previewActive : .previewClean
            SidebarRepoRow(repository: repo,
                           org: "9alvaro0",
                           branch: status.branch,
                           ahead: status.ahead,
                           behind: status.behind,
                           dirty: status.dirty,
                           isCurrent: isCurrent,
                           onSelect: {})
        }
    }
    .frame(width: 256)
    .padding(.vertical, DesignTokens.Spacing.sm)
    .background(theme.palette.bg1)
    .appTheme(theme)
}
