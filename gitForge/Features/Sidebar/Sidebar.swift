import SwiftUI

/// v2 sidebar (redesign spec §6.1): repository switcher, workspace
/// navigation, local branch tree, remotes and tags, identity card.
/// Presentation only; `SidebarHost` wires the stores.
struct Sidebar: View {
    let repositories: [Repository]
    let activeRepository: Repository?
    /// Live status for any repo: the active VM (instant) or the catalog's
    /// background-polled snapshot.
    let statusFor: (Repository) -> RepoStatusSnapshot
    let activeSection: WorkspaceSection
    let unstagedBadge: Int
    let stashesBadge: Int
    let pullsBadge: Int
    let conflictsBadge: Int
    let refs: [GitRef]
    let identity: GitIdentity
    let scopeTag: SidebarUserCard.ScopeTag
    /// Network reachability for the user card's status dot.
    var online: Bool = true
    let profiles: [GitProfile]
    let activeProfileId: GitProfile.ID?
    let canResetIdentityToGlobal: Bool
    let identityMenuEnabled: Bool
    let onSelectRepo: (Repository) -> Void
    let onRemoveRepo: (Repository) -> Void
    let onRevealRepo: (Repository) -> Void
    let onOpenExisting: () -> Void
    let onCloneNew: () -> Void
    let onOpenSettings: () -> Void
    let onSelectSection: (WorkspaceSection) -> Void
    let onRevealBranch: (GitRef) -> Void
    let onCheckoutBranch: (GitRef) -> Void
    let onApplyProfile: (GitProfile) -> Void
    let onResetToGlobal: () -> Void
    let onManageProfiles: () -> Void

    @State private var collapsedFolders: Set<String> = []

    var body: some View {
        List {
            if activeRepository != nil {
                Section {
                    ForEach(WorkspaceSection.workspaceItems) { section in
                        SidebarNavItem(
                            section: section,
                            badge: badge(for: section),
                            isActive: section == activeSection,
                            onSelect: { onSelectSection(section) }
                        )
                    }
                }
                Section("Branches") {
                    ForEach(BranchTree.rows(for: refs, collapsed: collapsedFolders)) { row in
                        SidebarBranchRow(
                            row: row,
                            onToggleFolder: toggleFolder,
                            onReveal: onRevealBranch,
                            onCheckout: onCheckoutBranch,
                            onShowInBranches: { onSelectSection(.branches) }
                        )
                    }
                }
                Section {
                    SidebarRefSummaryRow(systemImage: "cloud", title: "Remotes", detail: remotesDetail) {
                        onSelectSection(.branches)
                    }
                    SidebarRefSummaryRow(systemImage: "tag", title: "Tags", detail: "\(refs.filter(\.isTag).count)") {
                        onSelectSection(.branches)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            SidebarRepoSwitcher(
                repositories: repositories,
                activeRepository: activeRepository,
                statusFor: statusFor,
                onSelectRepo: onSelectRepo,
                onRemoveRepo: onRemoveRepo,
                onRevealRepo: onRevealRepo,
                onOpenExisting: onOpenExisting,
                onCloneNew: onCloneNew,
                onOpenSettings: onOpenSettings
            )
            .padding(.horizontal, Spacing.s8)
            .padding(.bottom, Spacing.s8)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarUserCard(
                identity: identity,
                scopeTag: scopeTag,
                online: online,
                profiles: profiles,
                activeProfileId: activeProfileId,
                canResetToGlobal: canResetIdentityToGlobal,
                menuEnabled: identityMenuEnabled,
                onApplyProfile: onApplyProfile,
                onResetToGlobal: onResetToGlobal,
                onManageProfiles: onManageProfiles
            )
        }
    }

    private var remotesDetail: String {
        let names = BranchTree.remoteNames(in: refs)
        return names.isEmpty ? "none" : names.joined(separator: ", ")
    }

    private func toggleFolder(_ path: String) {
        if collapsedFolders.contains(path) {
            collapsedFolders.remove(path)
        } else {
            collapsedFolders.insert(path)
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
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var section: WorkspaceSection = .history
    let active = Repository.previewSamples.first
    Sidebar(
        repositories: Repository.previewSamples,
        activeRepository: active,
        statusFor: RepoStatusSnapshot.previewStatusFor(active: active),
        activeSection: section,
        unstagedBadge: 3, stashesBadge: 1, pullsBadge: 2, conflictsBadge: 0,
        refs: [
            GitRef(name: "main", kind: .localBranch, targetSha: "a", isHead: true),
            GitRef(name: "feature/lane-legend", kind: .localBranch, targetSha: "b", isHead: false),
            GitRef(name: "origin/main", kind: .remoteBranch(remote: "origin"), targetSha: "a", isHead: false),
            GitRef(name: "v1.0", kind: .tag, targetSha: "a", isHead: false),
        ],
        identity: .preview,
        scopeTag: .profile("Personal"),
        profiles: GitProfile.previewSamples,
        activeProfileId: GitProfile.previewPersonal.id,
        canResetIdentityToGlobal: false,
        identityMenuEnabled: true,
        onSelectRepo: { _ in },
        onRemoveRepo: { _ in },
        onRevealRepo: { _ in },
        onOpenExisting: {},
        onCloneNew: {},
        onOpenSettings: {},
        onSelectSection: { section = $0 },
        onRevealBranch: { _ in },
        onCheckoutBranch: { _ in },
        onApplyProfile: { _ in },
        onResetToGlobal: {},
        onManageProfiles: {}
    )
    .frame(width: 240, height: 640)
    .appTheme(theme)
}
