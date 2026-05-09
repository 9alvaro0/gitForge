import Foundation

struct BranchFlatRow: Identifiable {
    enum Kind {
        case folder(path: String, name: String, leafCount: Int)
        case leaf(ref: GitRef, leafName: String)
    }
    let id: String
    let depth: Int
    let kind: Kind
}

/// `leafCount` is computed bottom-up here so folder rows don't recurse on
/// every render.
enum BranchFlatRowBuilder {
    static func build(refs: [GitRef], collapsedFolders: Set<String>) -> [BranchFlatRow] {
        let tree = BranchTreeBuilder.build(from: refs)
        var out: [BranchFlatRow] = []
        _ = walk(tree, depth: 0, collapsed: collapsedFolders, into: &out)
        return out
    }

    @discardableResult
    private static func walk(
        _ nodes: [BranchTreeNode],
        depth: Int,
        collapsed: Set<String>,
        into out: inout [BranchFlatRow]
    ) -> Int {
        var total = 0
        for node in nodes {
            switch node {
            case .ref(let leaf, let ref):
                out.append(BranchFlatRow(id: node.id, depth: depth,
                                         kind: .leaf(ref: ref, leafName: leaf)))
                total += 1
            case .folder(let path, let name, let children):
                let isCollapsed = collapsed.contains(path)
                let placeholderIndex = out.count
                out.append(BranchFlatRow(id: node.id, depth: depth,
                                         kind: .folder(path: path, name: name, leafCount: 0)))
                let leafCount: Int
                if isCollapsed {
                    leafCount = countLeaves(in: children)
                } else {
                    leafCount = walk(children, depth: depth + 1, collapsed: collapsed, into: &out)
                }
                out[placeholderIndex] = BranchFlatRow(
                    id: node.id, depth: depth,
                    kind: .folder(path: path, name: name, leafCount: leafCount)
                )
                total += leafCount
            }
        }
        return total
    }

    private static func countLeaves(in nodes: [BranchTreeNode]) -> Int {
        nodes.reduce(0) { acc, node in
            switch node {
            case .ref:                          acc + 1
            case .folder(_, _, let children):   acc + countLeaves(in: children)
            }
        }
    }
}
