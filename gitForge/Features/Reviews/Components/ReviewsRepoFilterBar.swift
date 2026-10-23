import SwiftUI

/// The row under the inbox's header while it's narrowed to one repo (R2
/// Ruling 7), where Team / Mine no longer applies: the repo's path, a × that
/// shows every repo again, and its clone or open button.
struct ReviewsRepoFilterBar: View {
    let repo: ReviewRepo
    let onShowAll: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: Spacing.s6) {
            HStack(spacing: 0) {
                Text(verbatim: repo.host.slug)
                    .textRole(.callout, weight: .semibold)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)
                    // A nested GitLab path keeps both ends: group and repo.
                    .truncationMode(.middle)
                    .padding(.leading, Spacing.s8)
                    .help(Text(verbatim: "\(repo.host.host)/\(repo.host.slug)"))
                IconButton(symbol: "xmark", size: 10,
                           accessibilityLabel: String(localized: "Show all repositories"), action: onShowAll)
                    .help(String(localized: "Show all repositories"))
            }
            .background(RoundedRectangle(cornerRadius: Radius.control).fill(theme.colors.fillControl))
            ReviewRepoActionButton(repo: repo, size: .small)
                .fixedSize()
            Spacer(minLength: 0)
        }
    }
}

/// The repo's one action in Reviews (spec §4.3), as the detail offers it:
/// "Clone repository…" when it isn't on this Mac, else "Open in repository",
/// which goes to the clone's Pull requests.
struct ReviewRepoActionButton: View {
    let repo: ReviewRepo
    var size: GFButton.Size = .regular

    @Environment(AppState.self) private var appState

    var body: some View {
        switch ReviewRepoAction(repo) {
        case .clone(let url):
            GFButton(title: String(localized: "Clone repository…"), size: size) {
                appState.ui.requestClone(CloneRequest(initialURL: url))
            }
        case .openInRepository(let localURL):
            GFButton(title: String(localized: "Open in repository"), size: size) {
                Task { await openPullRequests(at: localURL) }
            }
        }
    }

    /// Makes the clone the active repository, then shows its Pull requests;
    /// a clone that can't be opened says why and leaves the section as it was.
    private func openPullRequests(at url: URL) async {
        do {
            try await appState.openRepository(at: url)
        } catch {
            appState.ui.presentedError = PresentedError(error: error)
            return
        }
        appState.ui.workspaceSection = .pulls
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    let instance = PreviewReviewsWorld.gitLab
    VStack(alignment: .leading, spacing: Spacing.s12) {
        ForEach([PreviewReviewsWorld.paymentsApp, PreviewReviewsWorld.ledger], id: \.self) { path in
            ReviewsRepoFilterBar(
                repo: ReviewRepo(host: RemoteHost.make(fullName: path, on: instance)!, accountId: UUID(),
                                 sources: [.activity], lastActivity: nil,
                                 cloneURL: "https://gitlab.example.test/\(path).git",
                                 localURL: path == PreviewReviewsWorld.paymentsApp
                                     ? URL(fileURLWithPath: "/Users/preview/Developer/payments-app") : nil),
                onShowAll: {})
        }
    }
    .padding(Spacing.s12)
    .frame(width: 380, alignment: .leading)
    .background(theme.colors.bgContent)
    .previewAppState(.preview)
    .appTheme(theme)
}
