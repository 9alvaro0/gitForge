import SwiftUI

/// The Branches & Tags table for one scope: column header and the folder
/// tree flattened into rows (`BranchFlatRowBuilder`).
struct BranchTable: View {
    let scope: BranchScope
    let refs: [GitRef]
    let currentBranchName: String?
    let availableTargets: [GitRef]
    @Binding var selectedID: String?
    let actions: BranchActions

    @State private var collapsedFolders: Set<String> = []
    @Environment(\.appTheme) private var theme

    var body: some View {
        GeometryReader { geo in
            let layout = BranchTableLayout(width: geo.size.width, scope: scope)
            VStack(spacing: 0) {
                BranchTableHeader(scope: scope, layout: layout)
                let rows = BranchFlatRowBuilder.build(refs: refs, collapsedFolders: collapsedFolders)
                if rows.isEmpty {
                    EmptyState(icon: scope == .tags ? .tag : .branch, title: emptyTitle)
                } else {
                    ScrollView {
                        // Lazy so a repo with thousands of remotes doesn't
                        // build every row up front.
                        LazyVStack(spacing: 0) {
                            ForEach(rows) { row in
                                render(row, layout: layout)
                            }
                        }
                        .padding(Spacing.s6)
                    }
                }
            }
        }
    }

    private var emptyTitle: String {
        switch scope {
        case .local: "No local branches"
        case .remote: "No remote branches"
        case .tags: "No tags"
        }
    }

    @ViewBuilder
    private func render(_ row: BranchFlatRow, layout: BranchTableLayout) -> some View {
        switch row.kind {
        case .leaf(let ref, let leafName):
            BranchRow(
                ref: ref,
                leafName: leafName,
                depth: row.depth,
                scope: scope,
                layout: layout,
                currentBranchName: currentBranchName,
                availableTargets: availableTargets,
                isSelected: selectedID == ref.id,
                onSelect: { selectedID = ref.id },
                actions: actions
            )
        case .folder(let path, let name, let leafCount):
            BranchFolderRow(
                name: name,
                depth: row.depth,
                leafCount: leafCount,
                isCollapsed: collapsedFolders.contains(path),
                onToggle: {
                    if collapsedFolders.contains(path) {
                        collapsedFolders.remove(path)
                    } else {
                        collapsedFolders.insert(path)
                    }
                }
            )
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var selected: String? = nil
    BranchTable(
        scope: .local,
        refs: GitRef.previewLocalNested,
        currentBranchName: "main",
        availableTargets: GitRef.previewLocalNested,
        selectedID: $selected,
        actions: .none
    )
    .frame(width: 760, height: 400)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
