import SwiftUI

/// Right-hand panel for the selected branch or tag: what it tracks, how far
/// it is from its upstream, its tip commit, and the actions that exist today.
struct BranchInspector: View {
    let ref: GitRef
    let currentBranchName: String?
    let actions: BranchActions

    @Environment(\.appTheme) private var theme
    @Environment(\.appPreferences) private var preferences

    private var isCurrent: Bool { ref.isLocalBranch && ref.name == currentBranchName }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            header
            if let ahead = ref.ahead, let behind = ref.behind, let upstream = ref.upstream, !ref.upstreamGone {
                HStack(spacing: Spacing.s8) {
                    countCard(value: "↑ \(ahead)", color: theme.colors.add, caption: "ahead of \(upstream)")
                    countCard(value: "↓ \(behind)", color: theme.colors.warn, caption: "behind \(upstream)")
                }
            }
            lastCommit
            Spacer(minLength: 0)
            actionButtons
        }
        .padding(Spacing.s16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s6) {
            Text(kindLabel)
                .textRole(.caption, weight: .semibold)
                .foregroundStyle(theme.colors.textQuaternary)
            Text(ref.displayName)
                .font(AppFont.mono(TypeRole.headline.size, weight: .semibold, family: theme.monoFont))
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
        return ref.upstreamGone ? "Tracked \(upstream), which no longer exists" : "Tracks \(upstream)"
    }

    /// Spec §4.2: the ahead/behind figures are the one `title`-size mono text.
    private func countCard(value: String, color: Color, caption: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(value)
                .font(AppFont.mono(TypeRole.title.size, weight: .semibold, family: theme.monoFont))
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
                if !isCurrent, let current = currentBranchName {
                    HStack(spacing: Spacing.s6) {
                        GFButton(title: "Merge into \(current)", fullWidth: true) { actions.merge(ref, nil) }
                            .help("Merge \(ref.displayName) into \(current)")
                        GFButton(title: "Rebase onto", fullWidth: true) { actions.rebase(ref) }
                            .help("Rebase \(current) onto \(ref.displayName)")
                    }
                }
                if ref.isLocalBranch {
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
