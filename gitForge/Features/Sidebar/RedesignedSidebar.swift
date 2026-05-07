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
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    SidebarSearchTrigger(action: onOpenCommandPalette)
                        .padding(.horizontal, 10)
                        .padding(.top, 4)
                        .padding(.bottom, 8)

                    SidebarSectionHeader(title: "Repositories") {
                        Menu {
                            Button("Open existing…") { onOpenExisting() }
                            Button("Clone new…") { onCloneNew() }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(theme.palette.fg3)
                                .frame(width: 16, height: 16)
                                .contentShape(.rect)
                        }
                        .menuStyle(.button)
                        .menuIndicator(.hidden)
                        .buttonStyle(.plain)
                        .fixedSize()
                        .help("Add repository")
                    }
                    VStack(spacing: 1) {
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
