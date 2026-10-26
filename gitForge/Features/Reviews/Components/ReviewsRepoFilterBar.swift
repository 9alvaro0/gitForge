import SwiftUI

/// The row at the top of Team and Mine's list while the inbox is narrowed to
/// one repo (R2 Ruling 7), where the tabs, which no longer apply, give way to
/// it: the repo's path, a × that shows every repo again, and its clone or
/// open button. A repo opened from a search that isn't followed has "Follow
/// this repository" before that button (R3 Ruling 13).
struct ReviewsRepoFilterBar: View {
    let repo: ReviewRepo
    /// The inbox the bar narrows, which its open button reads and moves.
    let reviews: ReviewsStore
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
        ReviewRepoActionButton(repo: repo, reviews: reviews, size: .small)
            .fixedSize()
    }
}

/// The repo's one action in Team and Mine (spec §4.3), as the detail offers
/// it: "Clone repository…" when it isn't on this Mac, else "Open in
/// repository", which goes to the clone's own list, Open. None for the
/// repository open in gitForge, which is where it would go.
struct ReviewRepoActionButton: View {
    let repo: ReviewRepo
    /// The inbox that shows `repo`: it knows the open repository, and goes to
    /// Open once the clone is open.
    let reviews: ReviewsStore
    var size: GFButton.Size = .regular
    /// Stretches the button to the width it's given.
    var fullWidth = false

    @Environment(AppState.self) private var appState

    var body: some View {
        if !reviews.isActive(repo) {
            button
        }
    }

    @ViewBuilder
    private var button: some View {
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

    /// Makes the clone the active repository, then shows its Pull requests on
    /// Open, its own list, which leaves the filter by repo (U1 Ruling D); a
    /// clone that can't be opened says why and leaves the section as it was.
    private func openPullRequests(at url: URL) async {
        do {
            try await appState.openRepository(at: url)
        } catch {
            appState.ui.presentedError = PresentedError(error: error)
            return
        }
        appState.ui.workspaceSection = .pulls
        reviews.tab = .open
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    let instance = PreviewReviewsWorld.gitLab
    let reviews = ReviewsStore.preview(.loaded)
    VStack(alignment: .leading, spacing: Spacing.s12) {
        ForEach([PreviewReviewsWorld.paymentsApp, PreviewReviewsWorld.ledger], id: \.self) { path in
            ReviewsRepoFilterBar(
                repo: ReviewRepo(host: RemoteHost.make(fullName: path, on: instance)!, accountId: UUID(),
                                 sources: [.activity], lastActivity: nil,
                                 cloneURL: "https://gitlab.example.test/\(path).git",
                                 localURL: path == PreviewReviewsWorld.paymentsApp
                                     ? URL(fileURLWithPath: "/Users/preview/Developer/payments-app") : nil),
                reviews: reviews, onShowAll: {})
        }
        // Opened from a search, not followed.
        ReviewsRepoFilterBar(
            repo: ReviewRepo(host: RemoteHost.make(fullName: PreviewReviewsWorld.ossLib, on: PreviewReviewsWorld.gitHub)!,
                             accountId: UUID(), sources: [], lastActivity: nil,
                             cloneURL: "https://github.com/\(PreviewReviewsWorld.ossLib).git", localURL: nil),
            reviews: reviews, onShowAll: {}, onFollow: {})
    }
    .padding(Spacing.s12)
    .frame(width: 380, alignment: .leading)
    .background(theme.colors.bgContent)
    .previewAppState(.preview)
    .appTheme(theme)
}
