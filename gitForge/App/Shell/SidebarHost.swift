import SwiftUI
import AppKit

/// Adapts `Sidebar` (a presentation-only view with a long parameter list) to
/// the `AppState` sub-stores, so `ShellView.body` doesn't have to reach into
/// every store to wire it.
struct SidebarHost: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pendingProfile: PendingProfileApply?
    @State private var remotes: [GitRemoteURL] = []

    /// The column shows the workspace sidebar, or the one of the Settings
    /// mode (settings-redesign §4.1). Both sit in a `Group` so the modifiers
    /// below stay in place whichever is showing.
    var body: some View {
        Group {
            if isInSettings {
                settingsSidebar.transition(.opacity)
            } else {
                workspaceSidebar.transition(.opacity)
            }
        }
        // A fade, and none with Reduce Motion.
        .animation(reduceMotion ? nil : Motion.standard, value: isInSettings)
        // Remotes live in `.git/config`, which the watcher doesn't follow:
        // read them again when a new remote's branches show up, and when the
        // app comes back to the front (a remote added in a terminal).
        .task(id: RemotesKey(repo: appState.catalog.activeRepository?.url,
                             fetched: Self.remoteNames(appState.catalog.activeViewModel?.refs ?? []))) {
            await reloadRemotes()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await reloadRemotes() }
        }
        .confirmationDialog(
            pendingProfile.map { String(localized: "Apply profile “\($0.profile.name)”?") } ?? "",
            isPresented: Binding(
                get: { pendingProfile != nil },
                set: { if !$0 { pendingProfile = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingProfile
        ) { pending in
            Button("Apply") {
                guard let vm = appState.catalog.activeViewModel else { return }
                let profile = pending.profile
                Task {
                    do { try await vm.applyProfile(profile) }
                    catch { appState.ui.presentedError = PresentedError(error: error, title: String(localized: "Couldn’t switch identity")) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(pending.diff.message)
        }
    }

    private var isInSettings: Bool { appState.ui.workspaceSection == .settings }

    private var settingsSidebar: some View {
        SettingsSidebar(
            selection: appState.ui.settingsPane,
            repositoryName: appState.catalog.activeRepository?.name,
            version: WhatsNewController.bundleVersion,
            canShowWhatsNew: appState.whatsNew.canShowFromMenu,
            onSelect: { appState.ui.settingsPane = $0 },
            onBack: { appState.ui.closeSettings() },
            onWhatsNew: { appState.whatsNew.showFromMenu() }
        )
    }

    private var workspaceSidebar: some View {
        let identitySnapshot = resolveIdentity()
        return Sidebar(
            repositories: appState.catalog.repositories,
            activeRepository: appState.catalog.activeRepository,
            statusFor: statusFor,
            activeSection: appState.ui.workspaceSection,
            order: appState.ui.sidebarOrder,
            unstagedBadge: appState.catalog.activeViewModel?.workingCopy.status.unstagedFiles.count ?? 0,
            stashesBadge: appState.catalog.activeViewModel?.stashes.count ?? 0,
            pullsBadge: appState.reviews.badgeCount,
            conflictsBadge: appState.catalog.activeViewModel?.conflicts.files.filter { !$0.resolved }.count ?? 0,
            refs: appState.catalog.activeViewModel?.refs ?? [],
            identity: identitySnapshot.identity,
            scopeTag: identitySnapshot.scopeTag,
            online: appState.network.isOnline,
            profiles: appState.profiles.profiles,
            activeProfileId: identitySnapshot.activeProfileId,
            canResetIdentityToGlobal: identitySnapshot.canResetToGlobal,
            identityMenuEnabled: appState.catalog.activeViewModel != nil,
            onSelectRepo: { repo in Task { await appState.activate(repo) } },
            onRemoveRepo: { repo in Task { await appState.catalog.remove(repo.url) } },
            onRevealRepo: { repo in NSWorkspace.shared.activateFileViewerSelecting([repo.url]) },
            onOpenExisting: { Task { await appState.presentOpenRepositoryPanel() } },
            onCloneNew: { appState.ui.requestClone() },
            onOpenSettings: { appState.ui.workspaceSection = .settings },
            onSelectSection: { appState.ui.workspaceSection = $0 },
            onRevealBranch: { ref in
                guard let vm = appState.catalog.activeViewModel else { return }
                appState.ui.workspaceSection = .history
                if !vm.history.revealInHistory(ref) {
                    appState.ui.activeToast = ToastMessage(
                        message: String(localized: "“\(ref.name)” isn’t in the loaded history"),
                        kind: .warn
                    )
                }
            },
            onCheckoutBranch: { ref in
                guard let vm = appState.catalog.activeViewModel else { return }
                Task {
                    switch await vm.checkoutBranch(ref) {
                    case .success:
                        appState.ui.activeToast = ToastMessage(message: String(localized: "Checked out \(ref.displayName)"), kind: .ok)
                    case .failure(let err):
                        appState.ui.activeToast = ToastMessage(
                            message: (err as? LocalizedError)?.errorDescription ?? err.localizedDescription,
                            kind: .error)
                    }
                }
            },
            onApplyProfile: { profile in
                guard let vm = appState.catalog.activeViewModel else { return }
                if let diff = Self.identityDiff(from: vm.repoIdentity, to: profile) {
                    pendingProfile = PendingProfileApply(profile: profile, diff: diff)
                } else {
                    Task {
                        do { try await vm.applyProfile(profile) }
                        catch { appState.ui.presentedError = PresentedError(error: error, title: String(localized: "Couldn’t switch identity")) }
                    }
                }
            },
            onResetToGlobal: {
                guard let vm = appState.catalog.activeViewModel else { return }
                Task { await vm.clearLocalIdentity() }
            },
            onManageProfiles: {
                appState.ui.workspaceSection = .settings
            },
            hostingSections: hostingSections(identitySnapshot.activeProfileId),
            onHostingEntry: handleHostingEntry,
            onReorder: { edit in
                // Without a repository the list is Pull requests alone, so
                // an edit that lands as the repository closes does nothing
                // (pulls-unified §4.7, Ruling 6).
                guard appState.catalog.activeRepository != nil else { return }
                appState.ui.sidebarOrder.apply(edit)
            }
        )
    }

    private struct RemotesKey: Hashable {
        let repo: URL?
        let fetched: Set<String>
    }

    /// Remotes that have remote-tracking branches.
    nonisolated static func remoteNames(_ refs: [GitRef]) -> Set<String> {
        Set(refs.compactMap { ref in
            if case .remoteBranch(let remote) = ref.kind { remote } else { nil }
        })
    }

    private func reloadRemotes() async {
        let fresh = await appState.catalog.activeViewModel?.cli.remotesWithURLs() ?? []
        if fresh != remotes { remotes = fresh }
    }

    private func hostingSections(_ activeProfileId: GitProfile.ID?) -> [RepoAccountSection] {
        guard let repo = appState.catalog.activeRepository else { return [] }
        return RepoAccountMenuModel.sections(remotes: remotes, repoPath: repo.url.path(percentEncoded: false),
                                             activeProfileId: activeProfileId,
                                             instances: appState.accounts.instances, accounts: appState.accounts.accounts,
                                             assignments: appState.accounts.assignments)
    }

    private func handleHostingEntry(_ section: RepoAccountSection, _ entry: RepoAccountSection.Entry) {
        guard let repo = appState.catalog.activeRepository else { return }
        let path = repo.url.path(percentEncoded: false)
        switch entry {
        case .automatic: appState.accounts.setChoice(nil, repoPath: path, remoteName: section.remote)
        case .account(let id, _, _): appState.accounts.setChoice(.account(id), repoPath: path, remoteName: section.remote)
        case .system: appState.accounts.setChoice(.system, repoPath: path, remoteName: section.remote)
        case .connect(let instanceId): appState.ui.connectAccountRequest = ConnectAccountRequest(instanceId: instanceId)
        }
    }

    static func identityDiff(from current: RepoIdentity?, to profile: GitProfile) -> IdentityDiff? {
        let currentName = current?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let currentEmail = current?.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let currentKey = current?.signingKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nextName = profile.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextEmail = profile.userEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextKey = profile.signingKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var lines: [String] = []
        let shownName = currentName.isEmpty ? "—" : currentName
        let shownEmail = currentEmail.isEmpty ? "—" : currentEmail
        if currentName != nextName { lines.append(String(localized: "Name: \(shownName) → \(nextName)")) }
        if currentEmail != nextEmail { lines.append(String(localized: "Email: \(shownEmail) → \(nextEmail)")) }
        if currentKey != nextKey {
            if nextKey.isEmpty {
                lines.append(String(localized: "Signing key: will be removed (commits won’t be GPG-signed here unless your global config signs them)."))
            } else if currentKey.isEmpty {
                lines.append(String(localized: "Signing key: will be set to \(nextKey)"))
            } else {
                lines.append(String(localized: "Signing key: \(currentKey) → \(nextKey)"))
            }
        }
        guard !lines.isEmpty else { return nil }
        let header = String(localized: "This writes user.name/email/signingkey to this repository’s .git/config (overrides global):")
        return IdentityDiff(message: header + "\n\n" + lines.joined(separator: "\n"))
    }

    /// Computes what the user card should display: the effective identity
    /// (active repo's local override or global fallback), plus a tag and the
    /// profile id matching its email — used to checkmark the active profile
    /// in the menu and to label the chip.
    private func resolveIdentity() -> IdentitySnapshot {
        // No active repo → fall back to the global identity, no scope chip,
        // no menu actions beyond "Manage profiles…".
        guard let vm = appState.catalog.activeViewModel else {
            let global = appState.gitEnvironment.globalConfig.identity
            return IdentitySnapshot(
                identity: global,
                scopeTag: .none,
                activeProfileId: appState.profiles.profiles.first {
                    $0.userEmail.lowercased() == (global.email ?? "").lowercased()
                }?.id,
                canResetToGlobal: false
            )
        }
        // Repo active but identity not yet read → fall back to global so the
        // card never flashes "—" during the brief refresh window.
        guard let repoIdentity = vm.repoIdentity else {
            let global = appState.gitEnvironment.globalConfig.identity
            return IdentitySnapshot(
                identity: global,
                scopeTag: .inherited,
                activeProfileId: nil,
                canResetToGlobal: false
            )
        }
        let identity = GitIdentity(name: repoIdentity.name, email: repoIdentity.email)
        let matched = appState.profiles.match(for: repoIdentity)
        let tag: SidebarUserCard.ScopeTag = {
            if let matched { return .profile(matched.name) }
            return repoIdentity.isLocal ? .custom : .inherited
        }()
        return IdentitySnapshot(
            identity: identity,
            scopeTag: tag,
            activeProfileId: matched?.id,
            canResetToGlobal: repoIdentity.isLocal
        )
    }

    /// Active repo: read straight from the live ViewModel so the pills update
    /// instantly as the user works. Other repos: cached snapshot refreshed by
    /// `RepositoryCatalog`'s background poller.
    private func statusFor(_ repo: Repository) -> RepoStatusSnapshot {
        if let active = appState.catalog.activeRepository,
           active.id == repo.id,
           let vm = appState.catalog.activeViewModel,
           vm.workingCopy.hasLoadedStatusOnce {
            return RepoStatusSnapshot(
                branch: vm.currentBranchName,
                dirty: vm.workingCopy.status.files.count,
                ahead: vm.aheadCount,
                behind: vm.behindCount,
                loaded: true
            )
        }
        return appState.catalog.repositoryStatuses[repo.url] ?? .empty
    }

    private struct IdentitySnapshot {
        let identity: GitIdentity
        let scopeTag: SidebarUserCard.ScopeTag
        let activeProfileId: GitProfile.ID?
        let canResetToGlobal: Bool
    }

    private struct PendingProfileApply: Identifiable {
        let id = UUID()
        let profile: GitProfile
        let diff: IdentityDiff
    }

    struct IdentityDiff: Equatable {
        let message: String
    }
}

#Preview("Sidebar — repo active") {
    SidebarHost()
        .previewAppState(.previewWithActive)
        .frame(width: 280, height: 720)
}

#Preview("Sidebar — welcome") {
    SidebarHost()
        .previewAppState(.preview)
        .frame(width: 280, height: 720)
}

#Preview("Sidebar — settings") {
    @Previewable @State var state = AppState.previewWithActive
    SidebarHost()
        .previewAppState(state)
        .frame(width: 280, height: 720)
        .onAppear { state.ui.workspaceSection = .settings }
}
