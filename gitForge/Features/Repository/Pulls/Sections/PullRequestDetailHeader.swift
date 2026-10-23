import SwiftUI

/// The button ahead of the review and merge ones: "Check out branch" where
/// the repository is open, or whichever one stands in for it.
enum HeaderLeadingAction {
    case checkout(running: Bool, action: () -> Void)
    case button(title: String, systemImage: String, action: () -> Void)
}

/// Top of the PR detail: state, number and host, the actions, the title,
/// who wants to merge what into what, and reviewers / labels.
struct PullRequestDetailHeader: View {
    let pullRequest: PullRequest
    let hostLabel: String?
    /// How the host writes the number (`!482` on GitLab); `#482` by default.
    var reference: String? = nil
    /// `owner/repo`, ahead of the host, where the list mixes repositories.
    var repositoryLabel: String? = nil
    let commitCount: Int?
    let reviewers: [PullRequestDetail.Reviewer]
    let labels: [String]
    let leading: HeaderLeadingAction
    /// Review and merge buttons, between the leading one and "Open on …";
    /// `compact` folds the review ones into a menu.
    var actions: (_ compact: Bool) -> AnyView = { _ in AnyView(EmptyView()) }

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            // The buttons share the state line while they fit, then take a
            // line of their own, then fold the review ones into a menu, then
            // wrap, rather than cutting their titles.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.s8) {
                    identity
                    Spacer(minLength: Spacing.s16)
                    buttons(compact: false)
                }
                VStack(alignment: .leading, spacing: Spacing.s8) {
                    identityOnItsLine
                    HStack(spacing: Spacing.s8) { buttons(compact: false) }
                }
                VStack(alignment: .leading, spacing: Spacing.s8) {
                    identityOnItsLine
                    HStack(spacing: Spacing.s8) { buttons(compact: true) }
                }
                VStack(alignment: .leading, spacing: Spacing.s8) {
                    identityOnItsLine
                    FlowLayout(spacing: Spacing.s8) { buttons(compact: true) }
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

    /// Beside the buttons: whole, so that line is only picked when it all fits.
    private var identity: some View {
        identityContent.fixedSize()
    }

    /// On a line of its own: it takes the detail's width, and a repository
    /// path too long for it (a nested GitLab group) is cut in the middle
    /// rather than widening the header past the column. Its ideal width is
    /// none, so the buttons alone decide which layout fits.
    private var identityOnItsLine: some View {
        identityContent.frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private var identityContent: some View {
        HStack(spacing: Spacing.s8) {
            PullRequestStatePill(state: pullRequest.state)
                .fixedSize()
            // Verbatim: a localized number would group its digits (#1,203).
            Text(verbatim: "\(reference ?? "#\(pullRequest.number)")\(identityDetail.map { " · \($0)" } ?? "")")
                .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
                .foregroundStyle(theme.colors.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    /// What follows the number: the repository, when named, then the host.
    /// "Open on …" keeps the host alone.
    private var identityDetail: String? {
        let parts = [repositoryLabel, hostLabel].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func buttons(compact: Bool) -> some View {
        switch leading {
        case .checkout(let running, let action):
            GFButton(title: running ? String(localized: "Checking out…") : String(localized: "Check out branch"),
                     disabled: running || pullRequest.state == .merged, action: action)
                .help("Fetch and check out \(pullRequest.sourceBranch)")
                .fixedSize()
        case .button(let title, let systemImage, let action):
            GFButton(title: title, systemImage: systemImage, action: action)
                .fixedSize()
        }
        actions(compact)
        if let url = pullRequest.webURL {
            GFButton(title: hostLabel.map { String(localized: "Open on \($0)") } ?? String(localized: "Open on the web"),
                     systemImage: "arrow.up.right") {
                ExternalURL.open(url)
            }
            .fixedSize()
        }
    }

    /// "author wants to merge N commits into target from source", wrapping
    /// onto another line rather than cutting the branch names. A name wider
    /// than the whole column is cut in the middle, on one line, instead of
    /// running past the column's edge.
    private var mergeLine: some View {
        FlowLayout(spacing: Spacing.s6, fitsWideItems: true) {
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

    /// Whole phrases per state and count so translations can reorder them.
    private var verb: String {
        switch (pullRequest.state, commitCount) {
        case (.merged, 1?): return String(localized: "merged 1 commit into")
        case (.merged, let n?): return String(localized: "merged \(n) commits into")
        case (.merged, nil): return String(localized: "merged commits into")
        case (.closed, 1?): return String(localized: "wanted to merge 1 commit into")
        case (.closed, let n?): return String(localized: "wanted to merge \(n) commits into")
        case (.closed, nil): return String(localized: "wanted to merge commits into")
        case (.open, 1?), (.draft, 1?): return String(localized: "wants to merge 1 commit into")
        case (.open, let n?), (.draft, let n?): return String(localized: "wants to merge \(n) commits into")
        case (.open, nil), (.draft, nil): return String(localized: "wants to merge commits into")
        }
    }

    /// The whole name in its tooltip, for when it's cut.
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
            .help(name)
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
        case .approved: String(localized: "approved")
        case .changesRequested: String(localized: "requested changes")
        case .pending: String(localized: "pending")
        }
    }
}
