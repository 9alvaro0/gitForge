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
    /// The order of the workspace sections (pulls-unified §4.7).
    var order: SidebarOrder = SidebarOrder()
    let unstagedBadge: Int
    let stashesBadge: Int
    /// Open pull requests waiting on the user, across every followed repo.
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
    /// "Hosting account" sections for the active repo (P4 spec §5.4).
    var hostingSections: [RepoAccountSection] = []
    var onHostingEntry: (RepoAccountSection, RepoAccountSection.Entry) -> Void = { _, _ in }
    /// A change to the order of the workspace sections, from a drag or from
    /// a section's context menu (pulls-unified §4.7).
    var onReorder: (SidebarOrder.Edit) -> Void = { _ in }

    @State private var collapsedFolders: Set<String> = []

    /// Whether a repository is open. The list then shows every section and
    /// they can be reordered; without one it is Pull requests alone and the
    /// saved order doesn't change (pulls-unified §4.7, Ruling 6).
    private var hasRepository: Bool { activeRepository != nil }

    var body: some View {
        // The profile card sits under the list rather than in a bottom
        // safe-area inset: the inset let the last rows (Tags) scroll behind
        // the transparent card and show through it.
        VStack(spacing: 0) {
            list
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
                onManageProfiles: onManageProfiles,
                hostingSections: hostingSections,
                onHostingEntry: onHostingEntry
            )
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(order.visible(hasRepository: hasRepository)) { section in
                    navItem(for: section)
                }
                .onMove(perform: hasRepository ? { offsets, destination in
                    onReorder(.move(fromOffsets: offsets, toOffset: destination))
                } : nil)
            }
            if activeRepository != nil {
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
                    SidebarRefSummaryRow(systemImage: "cloud", title: String(localized: "Remotes"), detail: remotesDetail) {
                        onSelectSection(.branches)
                    }
                    SidebarRefSummaryRow(systemImage: "tag", title: String(localized: "Tags"), detail: "\(refs.filter(\.isTag).count)") {
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
    }

    /// A section's row, with the menu and accessibility actions that move it
    /// when a repository is open. The row is identified by its section, so
    /// the active one stays marked wherever it ends up.
    @ViewBuilder
    private func navItem(for section: WorkspaceSection) -> some View {
        let item = SidebarNavItem(
            section: section,
            badge: badge(for: section),
            isActive: section == activeSection,
            onSelect: { onSelectSection(section) }
        )
        if hasRepository {
            item.sectionReordering(section, in: order, onEdit: onReorder)
        } else {
            item
        }
    }

    private var remotesDetail: String {
        let names = BranchTree.remoteNames(in: refs)
        return names.isEmpty ? String(localized: "none") : names.joined(separator: ", ")
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

/// The sidebar as the previews show it: with `active` open, or with none.
/// The order is the preview's own, so editing it never reaches the saved
/// settings.
@MainActor
private func previewSidebar(active: Repository?, section: Binding<WorkspaceSection>,
                            order: Binding<SidebarOrder>) -> some View {
    Sidebar(
        repositories: Repository.previewSamples,
        activeRepository: active,
        statusFor: RepoStatusSnapshot.previewStatusFor(active: active),
        activeSection: section.wrappedValue,
        order: order.wrappedValue,
        unstagedBadge: 3, stashesBadge: 1, pullsBadge: 4, conflictsBadge: 0,
        refs: active == nil ? [] : [
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
        onSelectSection: { section.wrappedValue = $0 },
        onRevealBranch: { _ in },
        onCheckoutBranch: { _ in },
        onApplyProfile: { _ in },
        onResetToGlobal: {},
        onManageProfiles: {},
        onReorder: { order.wrappedValue.apply($0) }
    )
    .frame(width: 240, height: 640)
}

#Preview("Repository open") {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var section: WorkspaceSection = .history
    @Previewable @State var order = SidebarOrder()
    previewSidebar(active: Repository.previewSamples.first, section: $section, order: $order)
        .appTheme(theme)
}

#Preview("No repository") {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var section: WorkspaceSection = .pulls
    @Previewable @State var order = SidebarOrder()
    previewSidebar(active: nil, section: $section, order: $order)
        .appTheme(theme)
}

#Preview("Custom order") {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var section: WorkspaceSection = .pulls
    // Built from a list, so that editing it never touches `UserDefaults`.
    @Previewable @State var order = SidebarOrder(saved: ["pulls", "conflict", "history", "changes", "branches", "stashes"])
    previewSidebar(active: Repository.previewSamples.first, section: $section, order: $order)
        .appTheme(theme)
}
