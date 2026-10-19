import SwiftUI

/// Right-hand panel for the selected branch or tag: what it tracks, how far
/// it is from its upstream and from the trunk, its tip commit, and actions.
struct BranchInspector: View {
    let ref: GitRef
    let currentBranchName: String?
    let actions: BranchActions
    /// `RepositoryViewModel.comparison(of:)`; nil leaves the section out.
    var loadComparison: (GitRef) async -> BranchComparison? = { _ in nil }
    /// The trunk's tip: a merge into the trunk changes the comparison while
    /// `ref` stays the same.
    var trunkTip: String? = nil

    @State private var comparison: BranchComparison?

    @Environment(\.appTheme) private var theme
    @Environment(\.appPreferences) private var preferences

    private struct ComparisonKey: Equatable {
        let ref: GitRef
        let trunkTip: String?
    }

    private var isCurrent: Bool { ref.isLocalBranch && ref.name == currentBranchName }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            header
            // Cards only when there is a difference; "in sync" reads in the
            // tracking line. The upstream is named there too, so the captions
            // stay short enough not to truncate.
            if let ahead = ref.ahead, let behind = ref.behind, ahead + behind > 0, !ref.upstreamGone {
                HStack(spacing: Spacing.s8) {
                    countCard(value: "↑ \(ahead)", color: theme.colors.add, caption: "ahead")
                    countCard(value: "↓ \(behind)", color: theme.colors.warn, caption: "behind")
                }
            }
            lastCommit
            if let comparison {
                trunkSection(comparison)
            }
            Spacer(minLength: 0)
            actionButtons
        }
        .padding(Spacing.s16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // `ref` carries its tip, so a moved branch reloads too; so does a
        // moved trunk.
        .task(id: ComparisonKey(ref: ref, trunkTip: trunkTip)) {
            comparison = nil
            comparison = await loadComparison(ref)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s6) {
            Text(kindLabel)
                .textRole(.caption, weight: .semibold)
                .foregroundStyle(theme.colors.textQuaternary)
            Text(ref.displayName)
                .font(AppFont.font(.headline, weight: .semibold, monoFamily: theme.monoFont, monospaced: true))
                .foregroundStyle(isCurrent ? theme.colors.accent : theme.colors.textPrimary)
                .lineLimit(2)
                .textSelection(.enabled)
            if let tracking = trackingLine {
                Text(tracking)
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
    }

    private var kindLabel: String {
        if ref.isTag { return "Tag" }
        if ref.isRemoteBranch { return "Remote branch" }
        return isCurrent ? "Current branch" : "Branch"
    }

    private var trackingLine: String? {
        guard ref.isLocalBranch else { return nil }
        guard let upstream = ref.upstream else { return "No upstream" }
        if ref.upstreamGone { return "Tracked \(upstream), which no longer exists" }
        let inSync = (ref.ahead ?? 0) == 0 && (ref.behind ?? 0) == 0
        return inSync ? "Tracks \(upstream) · in sync" : "Tracks \(upstream)"
    }

    /// Spec §4.2: the ahead/behind figures are the one `title`-size mono text.
    private func countCard(value: String, color: Color, caption: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(value)
                .font(AppFont.font(.title, weight: .semibold, monoFamily: theme.monoFont, monospaced: true))
                .foregroundStyle(color)
            Text(caption)
                .textRole(.caption)
                .foregroundStyle(theme.colors.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, Spacing.s12)
        .padding(.vertical, Spacing.s8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.control).fill(theme.colors.fillControl))
        .accessibilityElement(children: .combine)
    }

    // MARK: Last commit

    private var lastCommit: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            Text("Last commit")
                .textRole(.caption, weight: .semibold)
                .foregroundStyle(theme.colors.textQuaternary)
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s8) {
                Text(String(ref.targetSha.prefix(7)))
                    .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
                    .foregroundStyle(theme.colors.textTertiary)
                    .textSelection(.enabled)
                Text(ref.subject ?? "")
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(3)
            }
            if let date = ref.date {
                Text(preferences.dateDisplayMode.format(date))
                    .textRole(.caption)
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
    }

    // MARK: Trunk

    /// "Compared with main": how far apart they are, and the branch's
    /// newest commits the trunk doesn't have.
    private func trunkSection(_ comparison: BranchComparison) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s6) {
            Text("Compared with \(comparison.trunk)")
                .textRole(.caption, weight: .semibold)
                .foregroundStyle(theme.colors.textQuaternary)
            Text(trunkSummary(comparison))
                .textRole(.callout)
                .foregroundStyle(theme.colors.textSecondary)
            if !comparison.commitsNotInTrunk.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    ForEach(comparison.commitsNotInTrunk) { commit in
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.s8) {
                            Text(commit.shortSha)
                                .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
                                .foregroundStyle(theme.colors.textTertiary)
                            Text(commit.subject)
                                .textRole(.callout)
                                .foregroundStyle(theme.colors.textPrimary)
                                .lineLimit(1)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    let hidden = comparison.ahead - comparison.commitsNotInTrunk.count
                    if hidden > 0 {
                        Text("and \(hidden) more")
                            .textRole(.caption)
                            .foregroundStyle(theme.colors.textTertiary)
                    }
                }
            }
        }
    }

    private func trunkSummary(_ c: BranchComparison) -> String {
        switch (c.ahead, c.behind) {
        case (0, 0): return "Same commit as \(c.trunk)"
        case (0, let behind): return "Fully in \(c.trunk) · \(behind) behind"
        case (let ahead, 0): return "\(ahead) not in \(c.trunk) · up to date with it"
        case (let ahead, let behind): return "\(ahead) not in \(c.trunk) · \(behind) behind"
        }
    }

    // MARK: Actions

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: Spacing.s6) {
            if ref.isTag {
                GFButton(title: "Push to origin", fullWidth: true) { actions.pushTag(ref) }
                GFButton(title: "Delete tag…", style: .destructive, fullWidth: true) { actions.deleteTag(ref) }
            } else {
                GFButton(title: isCurrent ? "Checked out" : "Check out", disabled: isCurrent, fullWidth: true) {
                    actions.checkout(ref)
                }
                // Branch names go in the help: in the button they'd truncate.
                if !isCurrent, let current = currentBranchName {
                    GFButton(title: "Merge into current branch", fullWidth: true) { actions.merge(ref, nil) }
                        .help("Merge \(ref.displayName) into \(current)")
                    GFButton(title: "Rebase current branch onto this", fullWidth: true) { actions.rebase(ref) }
                        .help("Rebase \(current) onto \(ref.displayName)")
                }
                if ref.isLocalBranch {
                    GFButton(title: "Push", fullWidth: true) { actions.push(ref) }
                        .help(ref.upstream.map { "Push to \($0)" } ?? "Push and set its upstream")
                    GFButton(title: "Rename…", fullWidth: true) { actions.rename(ref) }
                    if !isCurrent {
                        GFButton(title: "Delete branch…", style: .destructive, fullWidth: true) { actions.delete(ref) }
                    }
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    BranchInspector(ref: .previewLocalFeature, currentBranchName: "main", actions: .none)
        .frame(width: 360, height: 600)
        .background(theme.colors.bgElevated)
        .appTheme(theme)
}
