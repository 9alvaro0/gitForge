import SwiftUI

/// `.gf-sidebar` — redesigned left rail. Owned only via Environment to keep it
/// pluggable from any host shell (App, previews).
struct RedesignedSidebar: View {
    let repositories: [Repository]
    let activeRepository: Repository?
    let activeBranch: String?
    let aheadCount: Int
    let behindCount: Int
    let dirtyCount: Int
    let activeSection: WorkspaceSection
    let unstagedBadge: Int
    let stashesBadge: Int
    let pullsBadge: Int
    let conflictsBadge: Int
    let identity: GitIdentity
    let onSelectRepo: (Repository) -> Void
    let onSelectSection: (WorkspaceSection) -> Void
    let onOpenCommandPalette: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    SidebarSearchTrigger(action: onOpenCommandPalette)
                        .padding(.horizontal, 10)
                        .padding(.top, 4)
                        .padding(.bottom, 8)

                    SidebarSectionHeader(title: "Repositories")
                    VStack(spacing: 1) {
                        ForEach(repositories) { repo in
                            SidebarRepoRow(
                                repository: repo,
                                org: orgName(for: repo),
                                branch: activeRepository?.id == repo.id ? activeBranch : nil,
                                ahead: activeRepository?.id == repo.id ? aheadCount : 0,
                                behind: activeRepository?.id == repo.id ? behindCount : 0,
                                dirty: activeRepository?.id == repo.id ? dirtyCount : 0,
                                isCurrent: activeRepository?.id == repo.id,
                                onSelect: { onSelectRepo(repo) }
                            )
                        }
                    }

                    SidebarSectionHeader(title: "Workspace")
                    VStack(spacing: 1) {
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
                .padding(.bottom, 12)
            }

            VStack(spacing: 1) {
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
            Rectangle().fill(theme.palette.lineStrong).frame(width: 1)
        }
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

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var section: WorkspaceSection = .history
    RedesignedSidebar(
        repositories: Repository.previewSamples,
        activeRepository: Repository.previewSamples.first,
        activeBranch: "feat/commit-graph",
        aheadCount: 7, behindCount: 1, dirtyCount: 3,
        activeSection: section,
        unstagedBadge: 3, stashesBadge: 1, pullsBadge: 2, conflictsBadge: 0,
        identity: GitIdentity(name: "Alvaro Guerra", email: "9alvaro0@gmail.com"),
        onSelectRepo: { _ in },
        onSelectSection: { section = $0 },
        onOpenCommandPalette: {}
    )
    .frame(width: 256, height: 600)
    .appTheme(theme)
}
