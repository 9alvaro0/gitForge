import SwiftUI
import AppKit

/// Shown when no repository is active (artboard `Welcome`): open and clone
/// on the left, recent repositories with their branch and state on the right.
struct WelcomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme
    @State private var recents = RecentsModel()
    @State private var filter = ""

    var body: some View {
        HStack(spacing: 0) {
            actions
                .frame(minWidth: 340, idealWidth: 480, maxWidth: 560, maxHeight: .infinity, alignment: .topLeading)
            Divider().overlay(theme.colors.separator)
            recentPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(theme.colors.bgElevated)
        }
        .background(theme.colors.bgContent)
        .task(id: appState.catalog.repositories.map(\.url)) {
            await recents.load(appState.catalog.repositories)
        }
    }

    // MARK: Left column

    private var actions: some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            Spacer(minLength: Spacing.s48)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.s4) {
                Text("gitForge").textRole(.largeTitle)
                Text("Version \(Self.version) · A native Git client for macOS")
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            VStack(spacing: Spacing.s8) {
                bigButton("Open a repository…", symbol: "folder", shortcut: "⌘O", prominent: false) {
                    Task { await appState.presentOpenRepositoryPanel() }
                }
                bigButton("Clone a repository…", symbol: "square.and.arrow.down", shortcut: "⌥⌘C", prominent: true) {
                    appState.ui.cloneRequest = CloneRequest()
                }
            }
            .frame(maxWidth: 360)
            .padding(.top, Spacing.s16)
            Spacer()
            footer
        }
        .padding(.horizontal, Spacing.s48)
        .padding(.bottom, Spacing.s32)
    }

    private func bigButton(_ title: String, symbol: String, shortcut: String, prominent: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.s12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(theme.colors.accent)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text(title)
                    .textRole(.body, weight: .semibold)
                    .foregroundStyle(prominent ? theme.colors.accent : theme.colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(shortcut)
                    .textRole(.monoSmall)
                    .foregroundStyle(prominent ? theme.colors.accent : theme.colors.textSecondary)
            }
            .padding(.horizontal, Spacing.s12)
            .frame(height: 48)
            .background(RoundedRectangle(cornerRadius: Radius.card)
                .fill(prominent ? theme.colors.accentSoft : theme.colors.bgElevated))
            .overlay(RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(prominent ? theme.colors.accent : theme.colors.strokeControl,
                              lineWidth: prominent ? 1.5 : 1))
            .contentShape(.rect(cornerRadius: Radius.card))
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: Spacing.s16) {
            Button("Settings") { appState.ui.workspaceSection = .settings }
                .buttonStyle(.link)
            Text(signedIn)
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .textRole(.callout)
    }

    private var signedIn: String {
        let logins = appState.accounts.accounts.filter(AccountGitCredentials.signs).compactMap(\.login)
        return logins.isEmpty ? "No accounts connected" : "Signed in as \(logins.joined(separator: " · "))"
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    // MARK: Recents

    private var filtered: [Repository] {
        let query = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return appState.catalog.repositories }
        return appState.catalog.repositories.filter {
            $0.name.lowercased().contains(query) || $0.path.lowercased().contains(query)
        }
    }

    private var recentPanel: some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            HStack(spacing: Spacing.s12) {
                Text("Recent").textRole(.headline)
                Spacer()
                TextField("Filter", text: $filter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                    .accessibilityLabel("Filter recent repositories")
            }
            if appState.catalog.repositories.isEmpty {
                EmptyState(icon: .folder, title: "No recent repositories",
                           subtitle: "Repositories you open or clone show up here.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filtered) { repo in
                            RecentRepositoryRow(
                                repo: repo,
                                state: recents.states[repo.url],
                                onSelect: { Task { await appState.activate(repo) } },
                                onRemove: { Task { await appState.catalog.remove(repo.url) } }
                            )
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.s32)
        .padding(.top, Spacing.s48)
        .padding(.bottom, Spacing.s24)
    }
}

#Preview("With recents") {
    @Previewable @State var theme = AppTheme()
    WelcomeView()
        .previewAppState(.preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}

#Preview("No recents") {
    @Previewable @State var theme = AppTheme()
    WelcomeView()
        .previewAppState(.previewEmpty)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}
