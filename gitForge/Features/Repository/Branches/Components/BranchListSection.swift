import SwiftUI

/// One section of the Branches view ("Local" / "Remote") rendered as a
/// hierarchical card with collapsible folders.
///
/// The section flattens the tree once per render into `[FlatRow]` so the body
/// can use a single `ForEach` (no recursive ViewBuilder) — and so each folder
/// already knows its leaf count without re-walking subtrees on every render.
struct BranchListSection: View {
    let title: String
    let refs: [GitRef]
    /// Local branches usable as merge destinations from this section.
    let availableTargets: [GitRef]
    /// `nil` for the Remote section (no inline Checkout, no HEAD pill).
    let currentBranchName: String?
    /// `sha → authorDate`, built once by the parent so each row is an O(1)
    /// lookup instead of an O(commits) `first(where:)`.
    let commitDateBySha: [String: Date]
    let onCheckout: (GitRef) -> Void
    let onRename: ((GitRef) -> Void)?
    let onDelete: ((GitRef) -> Void)?
    let onMerge: ((GitRef, GitRef?) -> Void)?
    let onRebase: ((GitRef) -> Void)?

    @State private var collapsedFolders: Set<String> = []
    @Environment(\.appTheme) private var theme

    var body: some View {
        let rows = flatRows
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            sectionHeader
            if rows.isEmpty {
                emptyState
            } else {
                VStack(spacing: DesignTokens.Spacing.none) {
                    tableHeader
                    ForEach(rows) { row in
                        renderRow(row)
                    }
                }
                .background(card)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
            }
        }
    }

    // MARK: Layout pieces

    private var sectionHeader: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Text(title.uppercased())
                .font(.system(size: FontSize.footnote, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(theme.palette.fg3)
            Text("\(refs.count)")
                .font(.system(size: FontSize.footnote))
                .foregroundStyle(theme.palette.fg3)
        }
        .padding(.leading, DesignTokens.Spacing.xxs)
    }

    private var emptyState: some View {
        Text("No branches.")
            .font(AppFont.sans(12))
            .foregroundStyle(theme.palette.fg3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignTokens.Spacing.xxl)
            .padding(.vertical, DesignTokens.Spacing.xxl)
            .background(card)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
            .fill(theme.palette.bg3)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .stroke(theme.palette.lineStrong, lineWidth: DesignTokens.Stroke.regular)
            )
    }

    private var tableHeader: some View {
        HStack {
            Spacer().frame(width: DesignTokens.IconSize.md)
            Text("NAME").frame(maxWidth: .infinity, alignment: .leading)
            Text("LAST COMMIT")
                .frame(width: BranchRowMetrics.lastCommitColumn, alignment: .leading)
            Spacer().frame(width: BranchRowMetrics.actionsColumn)
        }
        .font(AppFont.mono(10.5, family: theme.monoFont))
        .tracking(0.6)
        .foregroundStyle(theme.palette.fg3)
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.md)
        .background(theme.palette.bg4)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.palette.lineStrong).frame(height: DesignTokens.Stroke.regular)
        }
    }

    @ViewBuilder
    private func renderRow(_ row: FlatRow) -> some View {
        switch row.kind {
        case .leaf(let ref, let leafName):
            BranchLeafRow(
                ref: ref,
                leafName: leafName,
                depth: row.depth,
                currentBranchName: currentBranchName,
                availableTargets: availableTargets,
                lastCommitLabel: lastCommitLabel(for: ref),
                onCheckout: onCheckout,
                onRename: onRename,
                onDelete: onDelete,
                onMerge: onMerge,
                onRebase: onRebase
            )
        case .folder(let path, let name, let leafCount):
            BranchFolderRow(
                name: name,
                depth: row.depth,
                leafCount: leafCount,
                isCollapsed: collapsedFolders.contains(path),
                onToggle: { toggleFolder(path) }
            )
        }
    }

    // MARK: Tree → flat rows

    private struct FlatRow: Identifiable {
        enum Kind {
            case folder(path: String, name: String, leafCount: Int)
            case leaf(ref: GitRef, leafName: String)
        }
        let id: String
        let depth: Int
        let kind: Kind
    }

    private var flatRows: [FlatRow] {
        let tree = BranchTreeBuilder.build(from: refs)
        var out: [FlatRow] = []
        walk(tree, depth: 0, into: &out)
        return out
    }

    /// Walks the tree once and emits flat rows. `leafCount` is computed
    /// bottom-up here so folder rows don't recurse on every render.
    @discardableResult
    private func walk(_ nodes: [BranchTreeNode], depth: Int, into out: inout [FlatRow]) -> Int {
        var total = 0
        for node in nodes {
            switch node {
            case .ref(let leaf, let ref):
                out.append(FlatRow(id: node.id, depth: depth, kind: .leaf(ref: ref, leafName: leaf)))
                total += 1
            case .folder(let path, let name, let children):
                let collapsed = collapsedFolders.contains(path)
                let placeholderIndex = out.count
                out.append(FlatRow(id: node.id, depth: depth,
                                   kind: .folder(path: path, name: name, leafCount: 0)))
                let leafCount: Int
                if collapsed {
                    leafCount = countLeaves(in: children)
                } else {
                    leafCount = walk(children, depth: depth + 1, into: &out)
                }
                out[placeholderIndex] = FlatRow(
                    id: node.id, depth: depth,
                    kind: .folder(path: path, name: name, leafCount: leafCount)
                )
                total += leafCount
            }
        }
        return total
    }

    private func countLeaves(in nodes: [BranchTreeNode]) -> Int {
        nodes.reduce(0) { acc, node in
            switch node {
            case .ref:                          acc + 1
            case .folder(_, _, let children):   acc + countLeaves(in: children)
            }
        }
    }

    private func toggleFolder(_ path: String) {
        if collapsedFolders.contains(path) {
            collapsedFolders.remove(path)
        } else {
            collapsedFolders.insert(path)
        }
    }

    private func lastCommitLabel(for ref: GitRef) -> String {
        if let date = commitDateBySha[ref.targetSha] {
            return theme.dateDisplayMode.format(date)
        }
        return String(ref.targetSha.prefix(7))
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    BranchListSection(
        title: "Local",
        refs: GitRef.previewLocalNested,
        availableTargets: GitRef.previewLocalNested,
        currentBranchName: "main",
        commitDateBySha: [:],
        onCheckout: { _ in }, onRename: { _ in }, onDelete: { _ in },
        onMerge: { _, _ in }, onRebase: { _ in }
    )
    .frame(width: 760)
    .padding()
    .background(theme.palette.bg2)
    .appTheme(theme)
}
