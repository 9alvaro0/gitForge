import SwiftUI

/// `.gf-user` — sticky user identity card at the bottom of the sidebar.
/// When there's an active repo, the card surfaces that repo's *effective*
/// identity (local override → global fallback) plus a menu to switch
/// between saved profiles. Without a repo selected, the menu collapses to
/// "Manage profiles…" and the global identity is shown instead.
struct SidebarUserCard: View {
    let identity: GitIdentity
    /// Tag rendered next to the email — "Personal", "Mercadona", "Custom",
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
        HStack(spacing: DesignTokens.Spacing.lg) {
            Circle()
                .fill(LinearGradient(colors: [theme.palette.accent, gradientTail],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    Text(identity.initials)
                        .font(.system(size: FontSize.footnote, weight: .bold))
                        .foregroundStyle(theme.palette.accentFg)
                }
                .frame(width: DesignTokens.IconSize.huge, height: DesignTokens.IconSize.huge)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.hairline) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text(identity.displayName)
                        .font(AppFont.sans(12, weight: .medium))
                        .foregroundStyle(theme.palette.fg1)
                        .lineLimit(1)
                    if let label = scopeTag.label {
                        scopeBadge(label)
                    }
                }
                if let email = identity.email {
                    Text(email)
                        .font(AppFont.mono(10, family: theme.monoFont))
                        .foregroundStyle(theme.palette.fg3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Circle().fill(online ? theme.palette.ok : theme.palette.fg4)
                .frame(width: DesignTokens.Spacing.md, height: DesignTokens.Spacing.md)
                .overlay(Circle().stroke(theme.palette.bg3, lineWidth: DesignTokens.Stroke.thick))
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg3))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.bottom, DesignTokens.Spacing.xs)
        .padding(.top, DesignTokens.Spacing.md)
        .contentShape(.rect)
    }

    @ViewBuilder
    private var menuContents: some View {
        if menuEnabled, !profiles.isEmpty {
            Section("Switch profile") {
                ForEach(profiles) { profile in
                    Button {
                        onApplyProfile(profile)
                    } label: {
                        HStack {
                            Text(profile.name)
                            Spacer()
                            Text(profile.userEmail)
                                .foregroundStyle(.secondary)
                            if profile.id == activeProfileId {
                                Image(systemName: "checkmark")
                            }
                        }
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
        Button("Manage profiles…") { onManageProfiles() }
    }

    private func scopeBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: FontSize.caption, weight: .semibold))
            .foregroundStyle(theme.palette.fg2)
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.vertical, DesignTokens.Spacing.hairline)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).fill(theme.palette.bg2))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
    }

    private var gradientTail: Color {
        ThemePalette.lanePalette.last ?? theme.palette.accent
    }
}

#Preview("Profile match (work)") {
    @Previewable @State var theme = AppTheme()
    SidebarUserCard(
        identity: GitIdentity(name: "Alvaro Guerra", email: "alvaro.guerra@mercadona.es"),
        scopeTag: .profile("Mercadona"),
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
    .padding(.vertical, DesignTokens.Spacing.xl)
    .background(theme.palette.bg1)
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
    .padding(.vertical, DesignTokens.Spacing.xl)
    .background(theme.palette.bg1)
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
    .padding(.vertical, DesignTokens.Spacing.xl)
    .background(theme.palette.bg1)
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
    .padding(.vertical, DesignTokens.Spacing.xl)
    .background(theme.palette.bg1)
    .appTheme(theme)
}
