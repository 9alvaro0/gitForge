import SwiftUI

/// Single ref row inside `BranchListSection`. Shows the branch (or remote
/// branch) icon, leaf name, last-commit label and the per-row actions.
///
/// `currentBranchName` is `nil` for remote sections — those never render a
/// HEAD pill nor an inline Checkout (everything goes through the menu so the
/// row stays tidy).
struct BranchLeafRow: View {
    let ref: GitRef
    let leafName: String
    let depth: Int
    let currentBranchName: String?
    let availableTargets: [GitRef]
    let lastCommitLabel: String
    let onCheckout: (GitRef) -> Void
    let onRename: ((GitRef) -> Void)?
    let onDelete: ((GitRef) -> Void)?
    let onMerge: ((GitRef, GitRef?) -> Void)?
    let onRebase: ((GitRef) -> Void)?

    @Environment(\.appTheme) private var theme

    private var isCurrent: Bool {
        ref.isLocalBranch && ref.name == currentBranchName
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Spacer().frame(width: BranchRowMetrics.indent(depth: depth))
            currentBranchDot
            nameCell
            Text(lastCommitLabel)
                .font(AppFont.mono(12, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
                .frame(width: BranchRowMetrics.lastCommitColumn, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
            actions
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(isCurrent ? theme.palette.accent.opacity(DesignTokens.Opacity.faint) : .clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.palette.line).frame(height: DesignTokens.Stroke.regular)
        }
        .contentShape(.rect)
        .onTapGesture(count: 2) {
            guard !isCurrent else { return }
            onCheckout(ref)
        }
    }

    @ViewBuilder
    private var currentBranchDot: some View {
        let dot = DesignTokens.Spacing.sm
        if isCurrent {
            Circle().fill(theme.palette.accent).frame(width: dot, height: dot)
        } else {
            Color.clear.frame(width: dot, height: dot)
        }
    }

    private var nameCell: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            GFIcon(kind: ref.isRemoteBranch ? .cloud : .desktop,
                   size: 12, stroke: theme.palette.fg2)
            Text(leafName)
                .font(AppFont.mono(12, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg1)
            if isCurrent {
                Pill(text: "HEAD", kind: .neutral)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            if !isCurrent {
                GFButton(title: "Checkout", size: .small) { onCheckout(ref) }
            }
            OverflowMenu {
                if !isCurrent {
                    Button("Checkout") { onCheckout(ref) }
                }
                if let onMerge {
                    Menu("Merge \(ref.displayName) into…") {
                        if let current = currentBranchName, ref.name != current {
                            Button("\(current) (current)") { onMerge(ref, nil) }
                            Divider()
                        }
                        ForEach(otherTargets) { target in
                            Button(target.name) { onMerge(ref, target) }
                        }
                    }
                }
                if let onRebase, !isCurrent {
                    Button("Rebase \(currentBranchName ?? "current") onto this…") { onRebase(ref) }
                }
                if let onRename {
                    Divider()
                    Button("Rename…") { onRename(ref) }
                }
                if let onDelete, !isCurrent {
                    Divider()
                    Button("Delete…", role: .destructive) { onDelete(ref) }
                }
            }
        }
        .frame(width: BranchRowMetrics.actionsColumn, alignment: .trailing)
    }

    /// Local branches usable as a merge destination, minus this ref and the
    /// current branch (rendered as a separate "(current)" item).
    private var otherTargets: [GitRef] {
        availableTargets.filter { target in
            target.id != ref.id && target.name != currentBranchName
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    let main = GitRef(name: "main", kind: .localBranch, targetSha: "a1b2c3d4", isHead: true)
    let feature = GitRef(name: "feature/awesome", kind: .localBranch, targetSha: "deadbeef", isHead: false)
    let remote = GitRef(name: "origin/main", kind: .remoteBranch(remote: "origin"),
                        targetSha: "a1b2c3d4", isHead: false)
    return VStack(spacing: 0) {
        BranchLeafRow(
            ref: main, leafName: "main", depth: 0,
            currentBranchName: "main",
            availableTargets: [main, feature],
            lastCommitLabel: "2026-05-09",
            onCheckout: { _ in }, onRename: { _ in }, onDelete: { _ in },
            onMerge: { _, _ in }, onRebase: { _ in }
        )
        BranchLeafRow(
            ref: feature, leafName: "awesome", depth: 1,
            currentBranchName: "main",
            availableTargets: [main, feature],
            lastCommitLabel: "deadbee",
            onCheckout: { _ in }, onRename: { _ in }, onDelete: { _ in },
            onMerge: { _, _ in }, onRebase: { _ in }
        )
        BranchLeafRow(
            ref: remote, leafName: "main", depth: 0,
            currentBranchName: nil,
            availableTargets: [main, feature],
            lastCommitLabel: "2026-05-08",
            onCheckout: { _ in }, onRename: nil, onDelete: nil,
            onMerge: { _, _ in }, onRebase: { _ in }
        )
    }
    .frame(width: 720)
    .background(theme.palette.bg3)
    .appTheme(theme)
}
