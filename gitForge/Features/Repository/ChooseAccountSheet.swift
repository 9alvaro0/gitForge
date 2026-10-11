import SwiftUI

/// "Choose an account for this repository" (P4 spec §5.5).
struct ChooseAccountSheet: View {
    let request: AccountChooser.Request
    let profiles: [GitProfile]
    let activeProfileId: UUID?
    let onAnswer: (RepoAccountChoice?) -> Void

    @Environment(\.appTheme) private var theme
    @State private var selection: RepoAccountChoice?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            Text("Choose an account for this repository").textRole(.title)
            Text("\(request.remote.candidates.count) accounts on \(request.remote.host) could be used for \(request.remote.ownerRepo). gitForge will remember your choice for this repository.")
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
        .onAppear {
            let linked = request.remote.candidates.first { $0.linkedProfileId != nil && $0.linkedProfileId == activeProfileId }
            selection = (linked ?? request.remote.candidates.first).map { .account($0.id) }
        }
    }

    private func detail(_ account: HostingAccount) -> String {
        let profile = profiles.first { $0.id == account.linkedProfileId }?.name
        return [request.remote.host, profile.map { "linked to \($0)" }].compactMap { $0 }.joined(separator: " · ")
    }
}
