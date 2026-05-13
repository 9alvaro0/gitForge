import SwiftUI
import AppKit

/// Adapts `Sidebar` (a presentation-only view with a long parameter list) to
/// the `AppState` sub-stores, so `ShellView.body` doesn't have to reach into
/// every store to wire it.
struct SidebarHost: View {
    @Environment(AppState.self) private var appState
    @State private var pendingProfile: PendingProfileApply?

    var body: some View {
        let identitySnapshot = resolveIdentity()
        Sidebar(
            repositories: appState.catalog.repositories,
            activeRepository: appState.catalog.activeRepository,
            statusFor: statusFor,
            activeSection: appState.ui.workspaceSection,
            unstagedBadge: appState.catalog.activeViewModel?.status.unstagedFiles.count ?? 0,
            stashesBadge: appState.catalog.activeViewModel?.stashes.count ?? 0,
            pullsBadge: appState.catalog.activeViewModel?.pullRequests.count ?? 0,
            conflictsBadge: appState.catalog.activeViewModel?.conflictFiles.filter { !$0.resolved }.count ?? 0,
            identity: identitySnapshot.identity,
            scopeTag: identitySnapshot.scopeTag,
            profiles: appState.profiles.profiles,
            activeProfileId: identitySnapshot.activeProfileId,
            canResetIdentityToGlobal: identitySnapshot.canResetToGlobal,
            identityMenuEnabled: appState.catalog.activeViewModel != nil,
            onSelectRepo: { repo in Task { await appState.activate(repo) } },
            onRemoveRepo: { repo in Task { await appState.catalog.remove(repo.url) } },
            onRevealRepo: { repo in NSWorkspace.shared.activateFileViewerSelecting([repo.url]) },
            onOpenExisting: { Task { await appState.presentOpenRepositoryPanel() } },
            onCloneNew: { appState.ui.workspaceSection = .clone },
            onSelectSection: { appState.ui.workspaceSection = $0 },
            onOpenCommandPalette: { appState.ui.commandPaletteOpen = true },
            onApplyProfile: { profile in
                guard let vm = appState.catalog.activeViewModel else { return }
                if let diff = Self.identityDiff(from: vm.repoIdentity, to: profile) {
                    pendingProfile = PendingProfileApply(profile: profile, diff: diff)
                } else {
                    Task {
                        do { try await vm.applyProfile(profile) }
                        catch { appState.ui.presentedError = PresentedError(error: error, title: "Couldn’t switch identity") }
                    }
                }
            },
            onResetToGlobal: {
                guard let vm = appState.catalog.activeViewModel else { return }
                Task { await vm.clearLocalIdentity() }
            },
            onManageProfiles: {
                appState.ui.workspaceSection = .settings
            }
        )
        .confirmationDialog(
            pendingProfile.map { "Apply profile “\($0.profile.name)”?" } ?? "",
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
                    catch { appState.ui.presentedError = PresentedError(error: error, title: "Couldn’t switch identity") }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(pending.diff.message)
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
        if currentName != nextName { lines.append("Name: \(currentName.isEmpty ? "—" : currentName) → \(nextName)") }
        if currentEmail != nextEmail { lines.append("Email: \(currentEmail.isEmpty ? "—" : currentEmail) → \(nextEmail)") }
        if currentKey != nextKey {
            if nextKey.isEmpty {
                lines.append("Signing key: will be removed (commits won’t be GPG-signed here unless your global config signs them).")
            } else if currentKey.isEmpty {
                lines.append("Signing key: will be set to \(nextKey)")
            } else {
                lines.append("Signing key: \(currentKey) → \(nextKey)")
            }
        }
        guard !lines.isEmpty else { return nil }
        let header = "This writes user.name/email/signingkey to this repository’s .git/config (overrides global):"
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
           vm.hasLoadedStatusOnce {
            return RepoStatusSnapshot(
                branch: vm.currentBranchName,
                dirty: vm.status.files.count,
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
