import SwiftUI

/// "Choose an account for this repository" (P4 spec §5.5).
struct ChooseAccountSheet: View {
    let request: AccountChooser.Request
    let profiles: [GitProfile]
    /// "GitHub" / "GitLab" for the remote's instance; `nil` when unknown.
    var providerLabel: String?
    let onAnswer: (RepoAccountChoice?) -> Void

    @Environment(\.appTheme) private var theme
    @State private var selection: RepoAccountChoice?

    /// "2 GitLab accounts could be used for group/app. …"
    nonisolated static func summary(count: Int, provider: String?, host: String, ownerRepo: String) -> String {
        let kind = provider.map { "\($0) " } ?? ""
        let accounts = count == 1 ? "One \(kind)account" : "\(count) \(kind)accounts"
        let place = provider == nil ? " on \(host)" : ""
        return "\(accounts)\(place) could be used for \(ownerRepo). gitForge will remember your choice for this repository."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            Text("Choose an account for this repository").textRole(.title)
            Text(Self.summary(count: request.remote.candidates.count, provider: providerLabel,
                              host: request.remote.host, ownerRepo: request.remote.ownerRepo))
                .textRole(.callout).foregroundStyle(theme.colors.textSecondary)
            Picker("", selection: $selection) {
                ForEach(request.remote.candidates) { account in
                    VStack(alignment: .leading) {
                        Text(account.login ?? "Copied token")
                        Text(detail(account)).textRole(.caption).foregroundStyle(theme.colors.textTertiary)
                    }
                    .tag(Optional(RepoAccountChoice.account(account.id)))
                }
                VStack(alignment: .leading) {
                    Text("Use the system's credentials")
                    Text("Like before gitForge accounts (Keychain / credential helper).")
                        .textRole(.caption).foregroundStyle(theme.colors.textTertiary)
                }
                .tag(Optional(RepoAccountChoice.system))
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            HStack {
                Spacer()
                GFButton(title: "Cancel") { onAnswer(nil) }
                GFButton(title: "Use this account", style: .primary, disabled: selection == nil) { onAnswer(selection) }
            }
        }
        .padding(Spacing.s16)
        .frame(width: 440)
        // No default from the active profile (spec §5.5): an account linked
        // to it already wins in the resolver, so the chooser only shows when
        // none is.
        .onAppear { selection = request.remote.candidates.first.map { .account($0.id) } }
    }

    private func detail(_ account: HostingAccount) -> String {
        let profile = profiles.first { $0.id == account.linkedProfileId }?.name
        return [request.remote.host, profile.map { "linked to \($0)" }].compactMap { $0 }.joined(separator: " · ")
    }
}
