import SwiftUI

/// Top of the PR detail: state, number and host, the actions, the title,
/// who wants to merge what into what, and reviewers / labels.
struct PullRequestDetailHeader: View {
    let pullRequest: PullRequest
    let hostLabel: String?
    let commitCount: Int?
    let reviewers: [PullRequestDetail.Reviewer]
    let labels: [String]
    let checkingOut: Bool
    let onCheckout: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            HStack(spacing: Spacing.s8) {
                PullRequestStatePill(state: pullRequest.state)
                Text("#\(pullRequest.number)\(hostLabel.map { " · \($0)" } ?? "")")
                    .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
                    .foregroundStyle(theme.colors.textTertiary)
                Spacer(minLength: 0)
                GFButton(title: checkingOut ? "Checking out…" : "Check out branch",
                         disabled: checkingOut || pullRequest.state == .merged, action: onCheckout)
                    .help("Fetch and check out \(pullRequest.sourceBranch)")
                if let url = pullRequest.webURL {
                    GFButton(title: "Open on \(hostLabel ?? "the web")", systemImage: "arrow.up.right") {
                        ExternalURL.open(url)
                    }
                }
            }
            Text(pullRequest.title)
                .textRole(.title)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(3)
                .textSelection(.enabled)
            mergeLine
            if !reviewers.isEmpty || !labels.isEmpty {
                // Wraps instead of truncating in a narrow detail.
                FlowLayout(spacing: Spacing.s20) {
                    if !reviewers.isEmpty { reviewersView }
                    if !labels.isEmpty { labelsView }
                }
            }
        }
    }

    /// "author wants to merge N commits into target from source", wrapping
    /// onto a second line rather than cutting the branch names.
    private var mergeLine: some View {
        FlowLayout(spacing: Spacing.s6) {
            if let author = pullRequest.authorLogin {
                Avatar(name: author, size: 18, colorSeed: author)
                Text(author)
                    .textRole(.callout, weight: .semibold)
                    .foregroundStyle(theme.colors.textPrimary)
            }
            Text(verb)
                .textRole(.callout)
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize()
            branchChip(pullRequest.targetBranch)
            Text("from")
                .textRole(.callout)
                .foregroundStyle(theme.colors.textSecondary)
            branchChip(pullRequest.sourceBranch)
        }
    }

    private var verb: String {
        let commits = commitCount.map { $0 == 1 ? "1 commit" : "\($0) commits" } ?? "commits"
        switch pullRequest.state {
        case .merged: return "merged \(commits) into"
        case .closed: return "wanted to merge \(commits) into"
        case .open, .draft: return "wants to merge \(commits) into"
        }
    }

    private func branchChip(_ name: String) -> some View {
        Text(name)
            .font(AppFont.font(.monoSmall, weight: .semibold, monoFamily: theme.monoFont))
            .foregroundStyle(theme.colors.textSecondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, Spacing.s6)
            .frame(height: 18)
            .background(RoundedRectangle(cornerRadius: Radius.chip).fill(theme.colors.fillControl))
            .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(theme.colors.strokeControl, lineWidth: 1))
    }

    private var reviewersView: some View {
        FlowLayout(spacing: Spacing.s8) {
            Text("Reviewers")
                .textRole(.callout)
                .foregroundStyle(theme.colors.textTertiary)
            ForEach(reviewers) { reviewer in
                HStack(spacing: Spacing.s4) {
                    Image(systemName: symbol(for: reviewer.state))
                        .font(.system(size: 11, weight: .semibold))
                    Text(reviewer.login)
                    if reviewer.state == .pending {
                        Text("· pending").foregroundStyle(theme.colors.textTertiary)
                    }
                }
                .textRole(.callout, weight: reviewer.state == .pending ? .regular : .semibold)
                .foregroundStyle(color(for: reviewer.state))
                .fixedSize()
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(reviewer.login), \(spoken(reviewer.state))")
            }
        }
    }

    private var labelsView: some View {
        FlowLayout(spacing: Spacing.s6) {
            Text("Labels")
                .textRole(.callout)
                .foregroundStyle(theme.colors.textTertiary)
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .textRole(.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .padding(.horizontal, Spacing.s8)
                    .frame(height: 18)
                    .background(Capsule().fill(theme.colors.fillControl))
            }
        }
    }

    private func symbol(for state: PullRequestDetail.Reviewer.State) -> String {
        switch state {
        case .approved: "checkmark"
        case .changesRequested: "exclamationmark.bubble"
        case .pending: "circle.dashed"
        }
    }

    private func color(for state: PullRequestDetail.Reviewer.State) -> Color {
        switch state {
        case .approved: theme.colors.ok
        case .changesRequested: theme.colors.del
        case .pending: theme.colors.textSecondary
        }
    }

    private func spoken(_ state: PullRequestDetail.Reviewer.State) -> String {
        switch state {
        case .approved: "approved"
        case .changesRequested: "requested changes"
        case .pending: "pending"
        }
    }
}
