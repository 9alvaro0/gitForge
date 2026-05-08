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
            HStack(spacing: 9) {
                RepoMark(letter: String(org.prefix(1)))
                VStack(alignment: .leading, spacing: 1) {
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
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(height: DesignTokens.Sidebar.repoRow)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(rowBackground))
            .contentShape(.rect(cornerRadius: DesignTokens.Radius.md))
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            if let onRevealInFinder {
                Button("Reveal in Finder", action: onRevealInFinder)
            }
            if let onRemove {
                Divider()
                Button("Remove from Recents", role: .destructive, action: onRemove)
            }
        }
    }

    private var rowBackground: Color {
        if isCurrent { return theme.palette.bg4 }
        return hovering ? theme.palette.bg3 : .clear
    }
}

#if DEBUG
#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(spacing: 1) {
        SidebarRepoRow(repository: Repository.preview, org: "9alvaro0",
                       branch: "feat/commit-graph",
                       ahead: 7, behind: 1, dirty: 3,
                       isCurrent: true, onSelect: {})
        SidebarRepoRow(repository: Repository(url: URL(fileURLWithPath: "/code/api-core")),
                       org: "acme", branch: "main",
                       ahead: 0, behind: 0, dirty: 0,
                       isCurrent: false, onSelect: {})
        SidebarRepoRow(repository: Repository(url: URL(fileURLWithPath: "/code/mobile-app")),
                       org: "acme", branch: nil,
                       ahead: 0, behind: 0, dirty: 12,
                       isCurrent: false, onSelect: {})
    }
    .frame(width: 256)
    .padding(.vertical, 6)
    .background(theme.palette.bg1)
    .appTheme(theme)
}
#endif
