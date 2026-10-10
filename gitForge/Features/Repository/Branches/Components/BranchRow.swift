import SwiftUI

/// One branch or tag in the Branches & Tags table. Click selects it for the
/// inspector, double-click checks a branch out, and the context menu keeps
/// every action the old inline menu had.
struct BranchRow: View {
    let ref: GitRef
    let leafName: String
    let depth: Int
    let scope: BranchScope
    let layout: BranchTableLayout
    let currentBranchName: String?
    /// Local branches usable as merge destinations.
    let availableTargets: [GitRef]
    let isSelected: Bool
    let onSelect: () -> Void
    let actions: BranchActions

    @Environment(\.appTheme) private var theme
    @Environment(\.appPreferences) private var preferences
    @State private var hovering = false

    static let indentStep: CGFloat = 16
    static func indent(depth: Int) -> CGFloat { CGFloat(depth) * indentStep }

    private var isCurrent: Bool { ref.isLocalBranch && ref.name == currentBranchName }

    var body: some View {
        HStack(spacing: 0) {
            nameCell
                .frame(maxWidth: .infinity, alignment: .leading)
            if layout.upstream > 0 {
                upstreamCell.frame(width: layout.upstream, alignment: .leading)
            }
            if layout.commit > 0 {
                Text(String(ref.targetSha.prefix(7)))
                    .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: layout.commit, alignment: .leading)
            }
            if layout.subject > 0 {
                Text(ref.subject ?? "")
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
                    .frame(width: layout.subject, alignment: .leading)
            }
            Text(updatedLabel)
                .textRole(.callout)
                .foregroundStyle(theme.colors.textTertiary)
                .lineLimit(1)
                .frame(width: layout.updated, alignment: .trailing)
        }
        .padding(.horizontal, Spacing.s12)
        .frame(height: theme.density.metrics.rowBranch)
        .background(RoundedRectangle(cornerRadius: Radius.row).fill(rowFill))
        .contentShape(.rect(cornerRadius: Radius.row))
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) {
            guard !ref.isTag, !isCurrent else { return }
            actions.checkout(ref)
        }
        .simultaneousGesture(TapGesture().onEnded(onSelect))
        .contextMenu { menu }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { onSelect() }
        .accessibilityAction(named: "Check out") {
            guard !ref.isTag, !isCurrent else { return }
            actions.checkout(ref)
        }
    }

    private var rowFill: Color {
        if isSelected { return theme.colors.accentSoft }
        return hovering ? theme.colors.fillHover : .clear
    }

    // MARK: Cells

    private var nameCell: some View {
        HStack(spacing: Spacing.s8) {
            Spacer().frame(width: Self.indent(depth: depth))
            if ref.isTag {
                Image(systemName: "tag")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 16)
            } else {
                BranchLaneGlyph(color: BranchGlyphColor.of(ref, currentBranch: currentBranchName), isHead: isCurrent)
            }
            Text(leafName)
                .font(AppFont.font(.mono, weight: isCurrent ? .semibold : .regular, monoFamily: theme.monoFont))
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            if isCurrent {
                Text("HEAD")
                    .textRole(.caption, weight: .bold)
                    .foregroundStyle(theme.colors.accentOnFill)
                    .padding(.horizontal, Spacing.s4)
                    .background(RoundedRectangle(cornerRadius: Radius.badge).fill(theme.colors.accentFill))
            }
        }
        .padding(.trailing, Spacing.s8)
    }

    private var upstreamCell: some View {
        HStack(spacing: Spacing.s8) {
            if let ahead = ref.ahead, ahead > 0 {
                Text("↑\(ahead)").foregroundStyle(theme.colors.add)
            }
            if let behind = ref.behind, behind > 0 {
                Text("↓\(behind)").foregroundStyle(theme.colors.warn)
            }
            Text(syncLabel).foregroundStyle(theme.colors.textQuaternary)
        }
        .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
        .lineLimit(1)
    }

    /// "gone" when the upstream was deleted, "in sync" when level with it,
    /// otherwise the remote's name next to the counts; empty without upstream.
    private var syncLabel: String {
        guard let upstream = ref.upstream else { return "" }
        if ref.upstreamGone { return "gone" }
        if (ref.ahead ?? 0) == 0 && (ref.behind ?? 0) == 0 { return "in sync" }
        return String(upstream.split(separator: "/").first ?? "")
    }

    private var updatedLabel: String {
        ref.date.map { preferences.dateDisplayMode.format($0) } ?? ""
    }

    private var spokenLabel: String {
        var parts = [ref.displayName]
        if isCurrent { parts.append("current branch") }
        if let ahead = ref.ahead, ahead > 0 { parts.append("\(ahead) ahead") }
        if let behind = ref.behind, behind > 0 { parts.append("\(behind) behind") }
        if ref.upstreamGone { parts.append("upstream gone") }
        if let subject = ref.subject { parts.append(subject) }
        if !updatedLabel.isEmpty { parts.append(updatedLabel) }
        return parts.joined(separator: ", ")
    }

    // MARK: Menu

    @ViewBuilder
    private var menu: some View {
        if ref.isTag {
            Button("Push to origin") { actions.pushTag(ref) }
            Divider()
            Button("Delete tag…", role: .destructive) { actions.deleteTag(ref) }
        } else {
            if !isCurrent {
                Button("Check out") { actions.checkout(ref) }
            }
            Menu("Merge \(ref.displayName) into…") {
                if let current = currentBranchName, ref.name != current {
                    Button("\(current) (current)") { actions.merge(ref, nil) }
                    Divider()
                }
                ForEach(otherTargets) { target in
                    Button(target.name) { actions.merge(ref, target) }
                }
            }
            if !isCurrent {
                Button("Rebase \(currentBranchName ?? "current") onto this…") { actions.rebase(ref) }
            }
            if ref.isLocalBranch {
                Divider()
                Button("Rename…") { actions.rename(ref) }
                if !isCurrent {
                    Button("Delete…", role: .destructive) { actions.delete(ref) }
                }
            }
        }
    }

    /// Local branches usable as a merge destination, minus this ref and the
    /// current branch (offered separately as "(current)").
    private var otherTargets: [GitRef] {
        availableTargets.filter { $0.id != ref.id && $0.name != currentBranchName }
    }
}
