import SwiftUI

/// User-managed list of git identity profiles. Profiles are inert until
/// applied to a repo via the sidebar — this section is just the catalog
/// (CRUD), it never writes anything to a repo's `.git/config` itself.
struct ProfilesSection: View {
    @Environment(ProfileStore.self) private var store
    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme

    /// Holds the in-progress edit/create form. `nil` when nothing is being
    /// edited; otherwise the row whose id matches expands into the form. New
    /// profiles use a sentinel UUID so they don't collide with existing ones.
    @State private var draft: ProfileDraft?

    var body: some View {
        SettingsSection(
            title: String(localized: "Profiles"),
            subtitle: String(localized: "Saved identities you can switch between per repository. Switching writes to that repo's local `.git/config`.")
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
        HStack(alignment: .top, spacing: Spacing.s12) {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text(profile.name)
                    .textRole(.headline)
                    .foregroundStyle(theme.colors.textPrimary)
                Text("\(profile.userName) · \(profile.userEmail)")
                    .textRole(.monoSmall)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let key = profile.signingKey, !key.isEmpty {
                    Text("Signing key: \(key)")
                        .textRole(.monoSmall)
                        .foregroundStyle(theme.colors.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Spacing.s6) {
                GFButton(title: String(localized: "Edit"), size: .small) {
                    draft = ProfileDraft(profile)
                }
                GFButton(title: String(localized: "Delete"), size: .small) {
                    store.remove(profile.id)
                    appState.accounts.unlinkProfile(profile.id)
                }
            }
        }
        .padding(.horizontal, Spacing.s12)
        .padding(.vertical, Spacing.s8)
    }

    private var addRow: some View {
        HStack {
            Spacer()
            GFButton(title: String(localized: "Add profile"), style: .primary, size: .small) {
                draft = ProfileDraft.new()
            }
        }
        .padding(.horizontal, Spacing.s12)
        .padding(.vertical, Spacing.s8)
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
        VStack(alignment: .leading, spacing: Spacing.s8) {
            field(String(localized: "Profile name"), placeholder: String(localized: "Personal"), text: $draft.name)
            field(String(localized: "Git name"), placeholder: "Ada Lovelace", text: $draft.userName)
            field(String(localized: "Git email"), placeholder: "ada@example.com", text: $draft.userEmail)
            field(String(localized: "Signing key (optional)"), placeholder: String(localized: "GPG / SSH key id"), text: $draft.signingKey)
            HStack {
                Spacer()
                GFButton(title: String(localized: "Cancel"), size: .small) { onCancel() }
                GFButton(title: String(localized: "Save"), style: .primary, size: .small) {
                    guard draft.canSave else { return }
                    onSave(draft.toProfile())
                }
                .disabled(!draft.canSave)
            }
        }
        .padding(.horizontal, Spacing.s12)
        .padding(.vertical, Spacing.s8)
    }

    @ViewBuilder
    private func field(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(label)
                .textRole(.callout, weight: .medium)
                .foregroundStyle(theme.colors.textTertiary)
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
        .padding(Spacing.s20)
        .background(theme.colors.bgContent)
        .appTheme(theme)
}
