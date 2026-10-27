import SwiftUI

/// A pull request among the Others (R2 Ruling 9): its row as in a repo's
/// group, with the repo's name for a host label since no group heading
/// names it, and a × that closes it.
struct ReviewOtherRow: View {
    let item: InboxPull
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    /// The ×'s inset from the row's top trailing corner.
    private static let closeInset = Spacing.s4
    /// `IconButton`'s square.
    private static let closeSide: CGFloat = 26

    var body: some View {
        let reference = item.repo.host.provider.reference(item.pull.number)
        PullRequestRow(
            pullRequest: item.pull,
            hostLabel: item.repo.host.repo,
            reference: reference,
            ci: nil,
            isSelected: isSelected,
            // The × holds the corner the shortcuts would take.
            offersShortcuts: false,
            // The first line stops short of the ×, with a gap: a long repo
            // name and a state pill never run under it.
            firstLineTrailingClearance: Self.closeInset + Self.closeSide + Spacing.s4,
            onSelect: onSelect
        )
        .help(Text(verbatim: "\(item.repo.host.host)/\(item.repo.host.slug)"))
        // Level with the reference line: no CI badge in Reviews.
        .overlay(alignment: .topTrailing) {
            IconButton(symbol: "xmark", size: 10,
                       accessibilityLabel: String(localized: "Close \(item.repo.host.repo) \(reference)"),
                       action: onClose)
                .help(String(localized: "Close"))
                .padding(.top, Self.closeInset)
                .padding(.trailing, Self.closeInset)
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    let instance = HostingInstance(kind: .github, host: "github.com")
    let repo = ReviewRepo(host: RemoteHost.make(fullName: "oss/lib", on: instance)!, accountId: UUID(),
                          sources: [], lastActivity: nil, cloneURL: "https://github.com/oss/lib.git", localURL: nil)
    VStack(spacing: Spacing.s2) {
        ForEach([(12, PullRequest.State.open), (9, .merged)], id: \.0) { number, state in
            ReviewOtherRow(
                item: InboxPull(repo: repo, pull: PullRequest(
                    id: "oss/lib#\(number)", number: number, title: "Parse dates in the server's time zone",
                    state: state, authorLogin: "octo", authorAvatarURL: nil, sourceBranch: "fix/server-time-zone",
                    targetBranch: "main", webURL: nil, createdAt: nil, updatedAt: .now.addingTimeInterval(-900))),
                isSelected: number == 12, onSelect: {}, onClose: {})
        }
    }
    .padding(Spacing.s8)
    .frame(width: 380)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
