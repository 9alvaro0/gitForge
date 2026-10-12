import SwiftUI

/// `.gf-user` — sticky user identity card at the bottom of the sidebar.
/// When there's an active repo, the card surfaces that repo's *effective*
/// identity (local override → global fallback) plus a menu to switch
/// between saved profiles. Without a repo selected, the menu collapses to
/// "Manage profiles…" and the global identity is shown instead.
struct SidebarUserCard: View {
    let identity: GitIdentity
    /// Tag rendered next to the email — "Personal", "Work", "Custom",
    /// or "Global". Computed by the host from `RepoIdentity` + matched
    /// profile so this view stays presentational.
    let scopeTag: ScopeTag
    let online: Bool
    let profiles: [GitProfile]
    /// `nil` when there's no active repo or the effective identity doesn't
    /// match any saved profile. Used to checkmark the active row in the menu.
    let activeProfileId: GitProfile.ID?
    /// `true` when the active repo has a `--local` override. Drives the
    /// "Use global identity" menu entry — hidden when no override exists.
    let canResetToGlobal: Bool
    /// `true` when the menu is meaningful (i.e. an active repo exists).
    let menuEnabled: Bool

    let onApplyProfile: (GitProfile) -> Void
    let onResetToGlobal: () -> Void
    let onManageProfiles: () -> Void
    /// "Hosting account" sections for the active repo (P4 spec §5.4).
    var hostingSections: [RepoAccountSection] = []
    var onHostingEntry: (RepoAccountSection, RepoAccountSection.Entry) -> Void = { _, _ in }

    @Environment(\.appTheme) private var theme

    enum ScopeTag: Equatable {
        case profile(String)
        case custom
        case inherited
        case none

        var label: String? {
            switch self {
            case .profile(let n): return n
            case .custom:         return "Custom"
            case .inherited:      return "Global"
            case .none:           return nil
            }
        }
    }

    var body: some View {
        Menu {
            menuContents
        } label: {
            cardContent
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .disabled(!menuEnabled && profiles.isEmpty)
        .help(menuEnabled ? "Switch git identity for this repository" : "Manage git profiles")
    }

    private var cardContent: some View {
        HStack(spacing: Spacing.s8) {
            Text(identity.initials)
                .textRole(.caption, weight: .bold)
                .foregroundStyle(theme.colors.accentOnFill)
                .frame(width: 28, height: 28)
                .background(Circle().fill(theme.colors.accentFill))
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Spacing.s6) {
                    Text(identity.displayName)
                        .textRole(.body, weight: .semibold)
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if let label = scopeTag.label {
                        scopeBadge(label)
                    }
                }
                if let email = identity.email {
                    Text(email)
                        .textRole(.monoSmall)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Circle().fill(online ? theme.colors.ok : theme.colors.textQuaternary)
                .frame(width: 8, height: 8)
                // Colour alone doesn't reach VoiceOver (or colour-blind users).
                .accessibilityLabel(online ? "Online" : "Offline")
                .help(online ? "Online" : "Offline")
        }
        .padding(.horizontal, Spacing.s12)
        .padding(.vertical, Spacing.s8)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.colors.separator).frame(height: 1)
        }
        .contentShape(.rect)
    }

    @ViewBuilder
    private var menuContents: some View {
        if menuEnabled, !profiles.isEmpty {
            Section("Switch profile") {
                ForEach(profiles) { profile in
                    MenuCheckItem(profile.name, subtitle: profile.userEmail, isChecked: profile.id == activeProfileId) {
                        onApplyProfile(profile)
                    }
                }
            }
            if canResetToGlobal {
                Divider()
                Button("Use global identity") { onResetToGlobal() }
            }
            Divider()
        } else if !profiles.isEmpty {
            Section("Profiles") {
                ForEach(profiles) { profile in
                    Text("\(profile.name) — \(profile.userEmail)")
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
        }
        ForEach(hostingSections) { section in
            Section(section.title) {
                Menu(section.current) {
                    ForEach(section.entries) { entry in
                        hostingButton(section, entry)
                    }
                }
            }
            Divider()
        }
        Button("Manage profiles…") { onManageProfiles() }
    }

    @ViewBuilder
    private func hostingButton(_ section: RepoAccountSection, _ entry: RepoAccountSection.Entry) -> some View {
        switch entry {
        case .automatic(let label, let checked), .account(_, let label, let checked):
            MenuCheckItem(label, isChecked: checked) { onHostingEntry(section, entry) }
        case .system(let checked):
            Divider()
            MenuCheckItem("Use system credentials", isChecked: checked) { onHostingEntry(section, entry) }
        case .connect:
            Button("Connect account…") { onHostingEntry(section, entry) }
        }
    }

    /// One line, never wraps: the name truncates first.
    private func scopeBadge(_ text: String) -> some View {
        Text(text)
            .textRole(.caption, weight: .semibold)
            .foregroundStyle(theme.colors.textSecondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Spacing.s4)
            .background(RoundedRectangle(cornerRadius: Radius.badge).fill(theme.colors.fillControl))
    }
}

#Preview("Profile match (work)") {
    @Previewable @State var theme = AppTheme()
    SidebarUserCard(
        identity: GitIdentity(name: "Alvaro Guerra", email: "alvaro@work.example.com"),
        scopeTag: .profile("Work"),
        online: true,
        profiles: GitProfile.previewSamples,
        activeProfileId: GitProfile.previewWork.id,
        canResetToGlobal: true,
        menuEnabled: true,
        onApplyProfile: { _ in },
        onResetToGlobal: {},
        onManageProfiles: {}
    )
    .frame(width: 256)
    .padding(.vertical, Spacing.s12)
    .background(theme.colors.bgElevated)
    .appTheme(theme)
}

#Preview("Inherited from global") {
    @Previewable @State var theme = AppTheme()
    SidebarUserCard(
        identity: .preview,
        scopeTag: .inherited,
        online: true,
        profiles: GitProfile.previewSamples,
        activeProfileId: GitProfile.previewPersonal.id,
        canResetToGlobal: false,
        menuEnabled: true,
        onApplyProfile: { _ in },
        onResetToGlobal: {},
        onManageProfiles: {}
    )
    .frame(width: 256)
    .padding(.vertical, Spacing.s12)
    .background(theme.colors.bgElevated)
    .appTheme(theme)
}

#Preview("Custom (no profile match)") {
    @Previewable @State var theme = AppTheme()
    SidebarUserCard(
        identity: GitIdentity(name: "Alvaro Guerra", email: "alguerra@clientx.com"),
        scopeTag: .custom,
        online: true,
        profiles: GitProfile.previewSamples,
        activeProfileId: nil,
        canResetToGlobal: true,
        menuEnabled: true,
        onApplyProfile: { _ in },
        onResetToGlobal: {},
        onManageProfiles: {}
    )
    .frame(width: 256)
    .padding(.vertical, Spacing.s12)
    .background(theme.colors.bgElevated)
    .appTheme(theme)
}

#Preview("No active repo") {
    @Previewable @State var theme = AppTheme()
    SidebarUserCard(
        identity: .preview,
        scopeTag: .none,
        online: false,
        profiles: GitProfile.previewSamples,
        activeProfileId: nil,
        canResetToGlobal: false,
        menuEnabled: false,
        onApplyProfile: { _ in },
        onResetToGlobal: {},
        onManageProfiles: {}
    )
    .frame(width: 256)
    .padding(.vertical, Spacing.s12)
    .background(theme.colors.bgElevated)
    .appTheme(theme)
}
