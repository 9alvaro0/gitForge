import SwiftUI

/// The row under the inbox's header while it's narrowed to one repo (R2
/// Ruling 7), where Team / Mine no longer applies: the repo's path, a × that
/// shows every repo again, and its clone or open button. A repo opened from a
/// search that isn't followed has "Follow this repository" before that
/// button (R3 Ruling 13).
struct ReviewsRepoFilterBar: View {
    let repo: ReviewRepo
    let onShowAll: () -> Void
    /// Follows the repo; `nil` when it's followed already or can't be.
    var onFollow: (() -> Void)? = nil

    @Environment(\.appTheme) private var theme

    var body: some View {
        if let onFollow {
            // Two buttons crowd a narrow column: the path keeps a row of its
            // own rather than being cut to a few letters.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.s6) {
                    pathChip
                        .fixedSize()
                    followButton(onFollow)
                    actionButton
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: Spacing.s6) {
                    HStack(spacing: 0) {
                        pathChip
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: Spacing.s6) {
                        followButton(onFollow)
                        actionButton
                        Spacer(minLength: 0)
                    }
                }
            }
        } else {
            HStack(spacing: Spacing.s6) {
                pathChip
                actionButton
                Spacer(minLength: 0)
            }
        }
    }

    private var pathChip: some View {
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
    }

    private func followButton(_ onFollow: @escaping () -> Void) -> some View {
        GFButton(title: String(localized: "Follow this repository"), size: .small, action: onFollow)
            .fixedSize()
    }

    private var actionButton: some View {
        ReviewRepoActionButton(repo: repo, size: .small)
            .fixedSize()
    }
}

/// The repo's one action in Reviews (spec §4.3), as the detail offers it:
/// "Clone repository…" when it isn't on this Mac, else "Open in repository",
/// which goes to the clone's Pull requests.
struct ReviewRepoActionButton: View {
    let repo: ReviewRepo
    var size: GFButton.Size = .regular
    /// Stretches the button to the width it's given.
    var fullWidth = false

    @Environment(AppState.self) private var appState

    var body: some View {
        switch ReviewRepoAction(repo) {
        case .clone(let url):
            GFButton(title: String(localized: "Clone repository…"), size: size, fullWidth: fullWidth) {
                appState.ui.requestClone(CloneRequest(initialURL: url))
            }
        case .openInRepository(let localURL):
            GFButton(title: String(localized: "Open in repository"), size: size, fullWidth: fullWidth) {
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
        // Opened from a search, not followed.
        ReviewsRepoFilterBar(
            repo: ReviewRepo(host: RemoteHost.make(fullName: PreviewReviewsWorld.ossLib, on: PreviewReviewsWorld.gitHub)!,
                             accountId: UUID(), sources: [], lastActivity: nil,
                             cloneURL: "https://github.com/\(PreviewReviewsWorld.ossLib).git", localURL: nil),
            onShowAll: {}, onFollow: {})
    }
    .padding(Spacing.s12)
    .frame(width: 380, alignment: .leading)
    .background(theme.colors.bgContent)
    .previewAppState(.preview)
    .appTheme(theme)
}
