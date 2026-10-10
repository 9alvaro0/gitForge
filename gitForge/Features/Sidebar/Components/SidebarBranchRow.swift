import SwiftUI

/// A folder or local branch in the sidebar tree. Click reveals the tip in
/// History (the default action), double-click or the "Check out" accessibility
/// action checks it out.
struct SidebarBranchRow: View {
    let row: BranchTreeRow
    let onToggleFolder: (String) -> Void
    let onReveal: (GitRef) -> Void
    let onCheckout: (GitRef) -> Void
    let onShowInBranches: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        switch row.kind {
        case .folder(let path, let expanded):
            folder(path: path, expanded: expanded)
        case .branch(let ref):
            branch(ref)
        }
    }

    private func folder(path: String, expanded: Bool) -> some View {
        Button { onToggleFolder(path) } label: {
            HStack(spacing: Spacing.s6) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(AppFont.font(.caption, weight: .semibold))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 12)
                Image(systemName: "folder")
                    .foregroundStyle(theme.colors.textTertiary)
                Text(row.name)
                    .textRole(.body)
                    .foregroundStyle(theme.colors.textSecondary)
                if row.containsHead && !expanded {
                    Circle().fill(theme.colors.accent).frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(row.depth) * Spacing.s12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(row.name) folder")
        .accessibilityValue(expanded ? "expanded" : "collapsed")
    }

    /// A `Button`, not `onTapGesture`: inside the sidebar `List` plain tap
    /// gestures never receive the click. The double-click runs alongside it,
    /// so a checkout also re-reveals the tip, which is harmless.
    private func branch(_ ref: GitRef) -> some View {
        Button { onReveal(ref) } label: {
            branchLabel(ref)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            if !ref.isHead { onCheckout(ref) }
        })
        .help(ref.name)
        .contextMenu {
            Button("Reveal in History") { onReveal(ref) }
            Button("Check Out") { onCheckout(ref) }
                .disabled(ref.isHead)
            Divider()
            Button("Show in Branches") { onShowInBranches() }
        }
        .accessibilityLabel(ref.isHead ? "\(ref.name), current branch" : ref.name)
        .accessibilityAction(named: "Check out") { if !ref.isHead { onCheckout(ref) } }
    }

    private func branchLabel(_ ref: GitRef) -> some View {
        HStack(spacing: Spacing.s6) {
            Circle()
                .fill(row.containsHead ? theme.colors.accent : theme.colors.textQuaternary)
                .frame(width: 6, height: 6)
                .frame(width: 12)
            Text(row.name)
                .textRole(.monoSmall, weight: row.containsHead ? .semibold : .regular)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            if row.containsHead {
                Image(systemName: "checkmark")
                    .font(AppFont.font(.caption, weight: .bold))
                    .foregroundStyle(theme.colors.accent)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(row.depth) * Spacing.s12)
        .contentShape(.rect)
    }
}
