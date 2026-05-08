import SwiftUI

/// `.gf-sidebar` — redesigned left rail. Owned only via Environment to keep it
/// pluggable from any host shell (App, previews).
struct RedesignedSidebar: View {
    let repositories: [Repository]
    let activeRepository: Repository?
    /// Returns the live status for any repo. Parent decides whether to pull
    /// from the active VM (instant) or from `AppState.repositoryStatuses`
    /// (background-polled snapshot).
    let statusFor: (Repository) -> RepoStatusSnapshot
    let activeSection: WorkspaceSection
    let unstagedBadge: Int
    let stashesBadge: Int
    let pullsBadge: Int
    let conflictsBadge: Int
    let identity: GitIdentity
    let onSelectRepo: (Repository) -> Void
    let onRemoveRepo: (Repository) -> Void
    let onRevealRepo: (Repository) -> Void
    let onOpenExisting: () -> Void
    let onCloneNew: () -> Void
    let onSelectSection: (WorkspaceSection) -> Void
    let onOpenCommandPalette: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.none) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.none) {
                    SidebarSearchTrigger(action: onOpenCommandPalette)
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                        .padding(.top, DesignTokens.Spacing.xs)
                        .padding(.bottom, DesignTokens.Spacing.md)

                    SidebarSectionHeader(title: "Repositories") {
                        Menu {
                            addRepositoryMenuItems()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: FontSize.caption, weight: .semibold))
                                .foregroundStyle(theme.palette.fg3)
                                .frame(width: DesignTokens.IconSize.lg, height: DesignTokens.IconSize.lg)
                                .contentShape(.rect)
                        }
                        .menuStyle(.button)
                        .menuIndicator(.hidden)
                        .buttonStyle(.plain)
                        .fixedSize()
                        .help("Add repository")
                    }
                    VStack(spacing: DesignTokens.Spacing.hairline) {
                        ForEach(repositories) { repo in
                            let status = statusFor(repo)
                            SidebarRepoRow(
                                repository: repo,
                                org: orgName(for: repo),
                                branch: status.branch,
                                ahead: status.ahead,
                                behind: status.behind,
                                dirty: status.dirty,
                                loaded: status.loaded,
                                isCurrent: activeRepository?.id == repo.id,
                                onSelect: { onSelectRepo(repo) },
                                onRemove: { onRemoveRepo(repo) },
                                onRevealInFinder: { onRevealRepo(repo) }
                            )
                        }
                        AddRepositoryRow {
                            addRepositoryMenuItems()
                        }
                    }

                    if activeRepository != nil {
                        SidebarSectionHeader(title: "Workspace")
                        VStack(spacing: DesignTokens.Spacing.hairline) {
                            ForEach(WorkspaceSection.workspaceItems) { section in
                                SidebarNavItem(
                                    section: section,
                                    badge: badge(for: section),
                                    isActive: section == activeSection,
                                    onSelect: { onSelectSection(section) }
                                )
                            }
                        }
                    }
                }
                .padding(.bottom, DesignTokens.Spacing.xl)
            }

            VStack(spacing: DesignTokens.Spacing.hairline) {
                ForEach(WorkspaceSection.bottomItems) { section in
                    SidebarNavItem(
                        section: section,
                        badge: nil,
                        isActive: section == activeSection,
                        onSelect: { onSelectSection(section) }
                    )
                }
            }

            SidebarUserCard(identity: identity, online: true)
        }
        .frame(width: DesignTokens.Sidebar.width)
        .background(theme.palette.bg1)
        .overlay(alignment: .trailing) {
            Rectangle().fill(theme.palette.lineStrong).frame(width: DesignTokens.Stroke.regular)
        }
    }

    /// Single source of truth for the repository-add menu so the header `+`
    /// and the labelled `AddRepositoryRow` always offer the same actions.
    @ViewBuilder
    private func addRepositoryMenuItems() -> some View {
        Button("Open existing folder…") { onOpenExisting() }
        Button("Clone new…") { onCloneNew() }
    }

    private func badge(for section: WorkspaceSection) -> Int? {
        switch section {
        case .changes:  return unstagedBadge > 0 ? unstagedBadge : nil
        case .stashes:  return stashesBadge > 0 ? stashesBadge : nil
        case .pulls:    return pullsBadge > 0 ? pullsBadge : nil
        case .conflict: return conflictsBadge > 0 ? conflictsBadge : nil
        default:        return nil
        }
    }

    private func orgName(for repo: Repository) -> String {
        let parent = repo.url.deletingLastPathComponent().lastPathComponent
        return parent.isEmpty ? repo.name : parent
    }
}

/// Explicit "add another repo" affordance under the repos list. The header `+`
/// menu hides this — a labelled row is unmistakable, especially right after
/// the existing repos finish. Menu items are injected so both entry points
/// stay in sync.
private struct AddRepositoryRow<Items: View>: View {
    @ViewBuilder var items: () -> Items

    @Environment(\.appTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Menu {
            items()
        } label: {
            HStack(spacing: DesignTokens.Spacing.lg) {
                Image(systemName: "plus")
                    .font(.system(size: FontSize.footnote, weight: .semibold))
                    .foregroundStyle(foreground.opacity(DesignTokens.Opacity.prominent))
                    .frame(width: DesignTokens.IconSize.md, height: DesignTokens.IconSize.md)
                Text("Add repository…")
                    .font(AppFont.sans(12))
                    .foregroundStyle(foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .frame(height: DesignTokens.Sidebar.navRow)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(rowBackground))
            .contentShape(.rect(cornerRadius: DesignTokens.Radius.md))
            .padding(.horizontal, DesignTokens.Spacing.sm)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Add a repository — open a local folder or clone a remote URL")
    }

    private var foreground: Color {
        hovering ? theme.palette.fg1 : theme.palette.fg3
    }
    private var rowBackground: Color {
        hovering ? theme.palette.bg3 : .clear
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var section: WorkspaceSection = .history
    RedesignedSidebar(
        repositories: Repository.previewSamples,
        activeRepository: Repository.previewSamples.first,
        statusFor: { repo in
            repo.id == Repository.previewSamples.first?.id
                ? RepoStatusSnapshot(branch: "feat/commit-graph", dirty: 3, ahead: 7, behind: 1)
                : RepoStatusSnapshot(branch: "main", dirty: 0, ahead: 0, behind: 0)
        },
        activeSection: section,
        unstagedBadge: 3, stashesBadge: 1, pullsBadge: 2, conflictsBadge: 0,
        identity: GitIdentity(name: "Alvaro Guerra", email: "9alvaro0@gmail.com"),
        onSelectRepo: { _ in },
        onRemoveRepo: { _ in },
        onRevealRepo: { _ in },
        onOpenExisting: {},
        onCloneNew: {},
        onSelectSection: { section = $0 },
        onOpenCommandPalette: {}
    )
    .frame(width: 256, height: 600)
    .appTheme(theme)
}
