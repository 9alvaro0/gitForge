import SwiftUI

/// User-managed list of git identity profiles. Profiles are inert until
/// applied to a repo via the sidebar — this section is just the catalog
/// (CRUD), it never writes anything to a repo's `.git/config` itself.
struct ProfilesSection: View {
    @Environment(ProfileStore.self) private var store
    @Environment(\.appTheme) private var theme

    /// Holds the in-progress edit/create form. `nil` when nothing is being
    /// edited; otherwise the row whose id matches expands into the form. New
    /// profiles use a sentinel UUID so they don't collide with existing ones.
    @State private var draft: ProfileDraft?

    var body: some View {
        SettingsSection(
            title: "Profiles",
            subtitle: "Saved identities you can switch between per repository. Switching writes to that repo's local `.git/config`."
        ) {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        ForEach(Array(store.profiles.enumerated()), id: \.element.id) { index, profile in
            if index > 0 {
                SettingsDivider()
            }
            if draft?.id == profile.id, let snapshot = draft {
                ProfileEditor(initial: snapshot, onSave: { updated in
                    store.update(updated)
                    draft = nil
                }, onCancel: {
                    draft = nil
                })
            } else {
                profileRow(profile)
            }
        }
        if let snapshot = draft, snapshot.isNew {
            if !store.profiles.isEmpty {
                SettingsDivider()
            }
            ProfileEditor(initial: snapshot, onSave: { fresh in
                store.add(fresh)
                draft = nil
            }, onCancel: {
                draft = nil
            })
        } else {
            if !store.profiles.isEmpty {
                SettingsDivider()
            }
            addRow
        }
    }

    private func profileRow(_ profile: GitProfile) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.lg) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(profile.name)
                    .font(AppFont.sans(13, weight: .semibold))
                    .foregroundStyle(theme.palette.fg1)
                Text("\(profile.userName) · \(profile.userEmail)")
                    .font(AppFont.mono(11, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let key = profile.signingKey, !key.isEmpty {
                    Text("Signing key: \(key)")
                        .font(AppFont.mono(10, family: theme.monoFont))
                        .foregroundStyle(theme.palette.fg3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: DesignTokens.Spacing.sm) {
                GFButton(title: "Edit", size: .small) {
                    draft = ProfileDraft(profile)
                }
                GFButton(title: "Delete", size: .small) {
                    store.remove(profile.id)
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    private var addRow: some View {
        HStack {
            Spacer()
            GFButton(title: "Add profile", style: .primary, size: .small) {
                draft = ProfileDraft.new()
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

}

// MARK: Draft + Editor

private struct ProfileDraft: Equatable {
    var id: UUID
    var isNew: Bool
    var name: String
    var userName: String
    var userEmail: String
    var signingKey: String

    static func new() -> ProfileDraft {
        ProfileDraft(id: UUID(), isNew: true, name: "", userName: "", userEmail: "", signingKey: "")
    }

    init(_ profile: GitProfile) {
        self.id = profile.id
        self.isNew = false
        self.name = profile.name
        self.userName = profile.userName
        self.userEmail = profile.userEmail
        self.signingKey = profile.signingKey ?? ""
    }

    init(id: UUID, isNew: Bool, name: String, userName: String, userEmail: String, signingKey: String) {
        self.id = id
        self.isNew = isNew
        self.name = name
        self.userName = userName
        self.userEmail = userEmail
        self.signingKey = signingKey
    }

    var canSave: Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let un = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let ue = userEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return !n.isEmpty && !un.isEmpty && !ue.isEmpty && ue.contains("@") && ue.contains(".")
    }

    func toProfile() -> GitProfile {
        GitProfile(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            userName: userName.trimmingCharacters(in: .whitespacesAndNewlines),
            userEmail: userEmail.trimmingCharacters(in: .whitespacesAndNewlines),
            signingKey: signingKey.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
    }
}

/// Owns its own copy of the draft. Earlier the editor pulled a `Binding`
/// out of the parent's `@State var draft: ProfileDraft?` via
/// `Binding($draft)`, which traps on teardown because SwiftUI re-evaluates
/// `.disabled(!draft.canSave)` against the about-to-be-nilled optional
/// during teardown. Local `@State` sidesteps that by making the editor's
/// lifetime independent of the parent's optional.
private struct ProfileEditor: View {
    let onSave: (GitProfile) -> Void
    let onCancel: () -> Void

    @State private var draft: ProfileDraft
    @Environment(\.appTheme) private var theme

    init(initial: ProfileDraft, onSave: @escaping (GitProfile) -> Void, onCancel: @escaping () -> Void) {
        self._draft = State(initialValue: initial)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            field("Profile name", placeholder: "Personal", text: $draft.name)
            field("Git name", placeholder: "Ada Lovelace", text: $draft.userName)
            field("Git email", placeholder: "ada@example.com", text: $draft.userEmail)
            field("Signing key (optional)", placeholder: "GPG / SSH key id", text: $draft.signingKey)
            HStack {
                Spacer()
                GFButton(title: "Cancel", size: .small) { onCancel() }
                GFButton(title: "Save", style: .primary, size: .small) {
                    guard draft.canSave else { return }
                    onSave(draft.toProfile())
                }
                .disabled(!draft.canSave)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    @ViewBuilder
    private func field(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            Text(label)
                .font(.system(size: FontSize.footnote, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(theme.palette.fg3)
            GFTextField(placeholder: placeholder, text: text)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    ProfilesSection()
        .previewAppState(.preview)
        .frame(width: 640)
        .padding(DesignTokens.Spacing.huge)
        .background(theme.palette.bg2)
        .appTheme(theme)
}
