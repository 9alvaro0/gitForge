import SwiftUI

/// Active-repository button at the top of the sidebar. Opens a popover with
/// every repository (live status), plus open / clone / settings
/// (redesign spec §6.1).
struct SidebarRepoSwitcher: View {
    let repositories: [Repository]
    let activeRepository: Repository?
    let statusFor: (Repository) -> RepoStatusSnapshot
    let onSelectRepo: (Repository) -> Void
    let onRemoveRepo: (Repository) -> Void
    let onRevealRepo: (Repository) -> Void
    let onOpenExisting: () -> Void
    let onCloneNew: () -> Void
    let onOpenSettings: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: Spacing.s8) {
                Text(ShellStatus.initials(for: activeRepository?.name ?? ""))
                    .textRole(.caption, weight: .bold)
                    .foregroundStyle(theme.colors.accentOnFill)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: Radius.control).fill(theme.colors.accentFill))
                VStack(alignment: .leading, spacing: 0) {
                    Text(activeRepository?.name ?? "No repository")
                        .textRole(.body, weight: .semibold)
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(1)
                    Text(pathLabel)
                        .textRole(.monoSmall)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(AppFont.font(.caption))
                    .foregroundStyle(theme.colors.textTertiary)
            }
            .padding(Spacing.s8)
            .background(RoundedRectangle(cornerRadius: Radius.card).fill(theme.colors.fillControl))
            .contentShape(.rect(cornerRadius: Radius.card))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(activeRepository.map { "Repository \($0.name)" } ?? "Choose a repository")
        .accessibilityHint("Shows your repositories")
        .popover(isPresented: $isPresented, arrowEdge: .trailing) { popoverContent }
    }

    private var pathLabel: String {
        guard let url = activeRepository?.url else { return "Open or clone one" }
        return (url.path as NSString).abbreviatingWithTildeInPath
    }

    private var popoverContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Spacing.s2) {
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
                            onSelect: { isPresented = false; onSelectRepo(repo) },
                            onRemove: { onRemoveRepo(repo) },
                            onRevealInFinder: { onRevealRepo(repo) }
                        )
                    }
                }
                .padding(Spacing.s6)
            }
            .frame(maxHeight: 360)
            Divider()
            VStack(alignment: .leading, spacing: Spacing.s2) {
                popoverAction("Open existing folder…", systemImage: "folder", action: onOpenExisting)
                popoverAction("Clone repository…", systemImage: "square.and.arrow.down", action: onCloneNew)
                popoverAction("Settings…", systemImage: "gearshape", action: onOpenSettings)
            }
            .padding(Spacing.s6)
        }
        .frame(width: 300)
    }

    private func popoverAction(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            isPresented = false
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .textRole(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.s8)
                .frame(height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func orgName(for repo: Repository) -> String {
        let parent = repo.url.deletingLastPathComponent().lastPathComponent
        return parent.isEmpty ? repo.name : parent
    }
}
