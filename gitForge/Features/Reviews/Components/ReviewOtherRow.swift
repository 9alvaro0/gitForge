import SwiftUI

/// A pull request among the Others (R2 Ruling 9): its row as in a repo's
/// group, with the repo's name for a host label since no group heading
/// names it, and a × that closes it.
struct ReviewOtherRow: View {
    let item: InboxPull
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        PullRequestRow(
            pullRequest: item.pull,
            hostLabel: item.repo.host.repo,
            reference: item.repo.host.provider.reference(item.pull.number),
            ci: nil,
            isSelected: isSelected,
            onSelect: onSelect
        )
        .help(Text(verbatim: "\(item.repo.host.host)/\(item.repo.host.slug)"))
        // Level with the reference line, where the row leaves room: no CI
        // badge in Reviews.
        .overlay(alignment: .topTrailing) {
            IconButton(symbol: "xmark", size: 10, accessibilityLabel: String(localized: "Close"), action: onClose)
                .help(String(localized: "Close"))
                .padding(.top, Spacing.s4)
                .padding(.trailing, Spacing.s4)
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
