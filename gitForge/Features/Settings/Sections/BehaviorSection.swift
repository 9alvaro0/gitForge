import SwiftUI

/// Day-to-day behavior switches that aren't strictly git config or visuals:
/// destructive-action confirmations, default flags for stash/commit, and
/// commit signing. Sits between Git and Remote hosts in the page so the
/// user reads "what git does → what the app guards → who you are to git
/// servers".
struct BehaviorSection: View {
    @Environment(\.appTheme) private var theme
    @Environment(GitEnvironment.self) private var gitEnvironment
    @Environment(WorkspaceUI.self) private var ui

    var body: some View {
        SettingsSection(title: "Behavior") {
            toggleRow(
                label: "Confirm force push",
                description: "Show a dialog before pushing with --force-with-lease.",
                isOn: Binding(
                    get: { ui.theme.confirmForcePush },
                    set: { ui.theme.confirmForcePush = $0 }
                )
            )
            SettingsDivider()
            toggleRow(
                label: "Sign commits by default",
                description: signCommitsDescription,
                isOn: Binding(
                    get: { gitEnvironment.globalConfig.signCommits == true },
                    set: setSignCommits
                )
            )
            SettingsDivider()
            toggleRow(
                label: "Stash untracked files",
                description: "Pass --include-untracked to git stash so quick stashes capture new files too.",
                isOn: Binding(
                    get: { ui.theme.stashIncludeUntracked },
                    set: { ui.theme.stashIncludeUntracked = $0 }
                )
            )
            SettingsDivider()
            pickerRow(
                label: "Commits per page",
                description: "How many commits History fetches per round-trip. Bigger pages mean fewer reloads on huge repos at the cost of slower first paint.",
                current: "\(ui.theme.commitPageSize)",
                options: Self.pageSizeOptions
            ) { value in
                if let n = Int(value) { ui.theme.commitPageSize = n }
            }
            SettingsDivider()
            pickerRow(
                label: "Git command timeout",
                description: "Seconds before a stuck git subprocess is killed. Raise it if you hit timeouts on a slow network or very large fetches.",
                current: "\(ui.theme.gitTimeoutSeconds)s",
                options: Self.timeoutOptions
            ) { value in
                if let n = Int(value) { ui.theme.gitTimeoutSeconds = n }
            }
        }
    }

    private static let pageSizeOptions: [(String, String)] = [
        ("100", "100"), ("200", "200"), ("500", "500"), ("1000", "1000"),
    ]
    private static let timeoutOptions: [(String, String)] = [
        ("30", "30 seconds"), ("60", "1 minute"), ("120", "2 minutes"),
        ("300", "5 minutes"),
    ]

    private var signCommitsDescription: String {
        if gitEnvironment.globalConfig.signingKey?.isEmpty == false {
            return "Sets commit.gpgsign=true. Uses the signing key configured under Identity."
        }
        return "Sets commit.gpgsign=true. Configure a signing key under Identity for git to actually sign."
    }

    private func setSignCommits(_ enabled: Bool) {
        Task {
            do {
                try await gitEnvironment.setSignCommits(enabled)
            } catch {
                ui.presentedError = PresentedError(error: error, title: "Couldn’t update commit signing")
            }
        }
    }

    @ViewBuilder
    private func pickerRow(label: String,
                           description: String,
                           current: String,
                           options: [(String, String)],
                           onPick: @escaping (String) -> Void) -> some View {
        HStack(alignment: .top) {
            SettingsRowLabel(text: label)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                SettingsPicker(current: current) {
                    ForEach(options, id: \.0) { (raw, lbl) in
                        Button(lbl) { onPick(raw) }
                    }
                }
                .frame(maxWidth: 240)
                Text(description)
                    .font(AppFont.sans(11))
                    .foregroundStyle(theme.palette.fg3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    @ViewBuilder
    private func toggleRow(label: String, description: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top) {
            SettingsRowLabel(text: label)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Toggle("", isOn: isOn)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                Text(description)
                    .font(AppFont.sans(11))
                    .foregroundStyle(theme.palette.fg3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.md)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    BehaviorSection()
        .previewAppState(.preview)
        .frame(width: 560)
        .padding(DesignTokens.Spacing.huge)
        .background(theme.palette.bg2)
        .appTheme(theme)
}
