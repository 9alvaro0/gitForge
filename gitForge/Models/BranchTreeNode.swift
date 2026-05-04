import Foundation

nonisolated indirect enum BranchTreeNode: Sendable, Identifiable, Hashable {
    case folder(path: String, name: String, children: [BranchTreeNode])
    case ref(leafName: String, ref: GitRef)

    var id: String {
        switch self {
        case .folder(let path, _, _): "folder:\(path)"
        case .ref(_, let ref): "ref:\(ref.id)"
        }
    }

    var displayName: String {
        switch self {
        case .folder(_, let name, _): name
        case .ref(let leaf, _): leaf
        }
    }

    /// Used by `OutlineGroup`. `nil` marks a leaf so the outline shows no chevron.
    var children: [BranchTreeNode]? {
        switch self {
        case .folder(_, _, let kids): kids
        case .ref: nil
        }
    }

    var ref: GitRef? {
        if case .ref(_, let ref) = self { return ref } else { return nil }
    }
}

enum BranchTreeBuilder {
    static func build(from refs: [GitRef]) -> [BranchTreeNode] {
        var roots: [BranchTreeNode] = []
        for ref in refs.sorted(by: { $0.displayName < $1.displayName }) {
            let segments = ref.displayName.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            insert(ref, segments: ArraySlice(segments), into: &roots, pathPrefix: "")
        }
        return roots
    }

    private static func insert(
        _ ref: GitRef,
        segments: ArraySlice<String>,
        into nodes: inout [BranchTreeNode],
        pathPrefix: String
    ) {
        guard let first = segments.first else { return }
        let rest = segments.dropFirst()

        if rest.isEmpty {
            nodes.append(.ref(leafName: first, ref: ref))
            return
        }

        let folderPath = pathPrefix.isEmpty ? first : "\(pathPrefix)/\(first)"

        if let index = nodes.firstIndex(where: { node in
            if case .folder(let p, _, _) = node, p == folderPath { return true }
            return false
        }) {
            if case .folder(let path, let name, var children) = nodes[index] {
                insert(ref, segments: rest, into: &children, pathPrefix: folderPath)
                nodes[index] = .folder(path: path, name: name, children: children)
            }
        } else {
            var children: [BranchTreeNode] = []
            insert(ref, segments: rest, into: &children, pathPrefix: folderPath)
            nodes.append(.folder(path: folderPath, name: first, children: children))
        }
    }
}
